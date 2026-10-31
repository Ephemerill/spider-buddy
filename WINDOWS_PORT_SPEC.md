# Spider Buddy for Windows — Build Specification

A from-scratch build guide for a 1-to-1 Windows port of **Spider Buddy**, the macOS desktop pet: a hand-animated jumping spider that lives on your screen, walks the edges of your windows, swings on silk, hunts bugs, plays with toys, and has a glass terrarium ("the habitat") to live in.

**How to read this document.** It is ordered by build order. Each **Stage** produces something you can run and check before moving on; later stages assume earlier ones. Every stage has the same shape:

- **Goal** — what exists when the stage is done.
- **Spec** — the behavior, data and numbers to reproduce.
- **Windows mapping** — how the macOS mechanism translates (where there is one).
- **Done when** — acceptance checks.

**What this document is, and is not.** It is derived from the macOS source (77k lines of Swift, v1.0.1) and from the design rules the product's owner has given over many iterations. It specifies behavior, data structures, algorithms, and every constant that could be recovered. Where an exact number lives only in the art or in a long tuning table (for example, the precise outline of each hat), the text says so and names the macOS source file to read. The macOS build is the **reference oracle**: keep it running next to your port and compare side by side. Section "Source map" at the end lists which Swift file answers which question.

Contents of the stages:

| Part | Stage | What you build |
|---|---|---|
| A | 0 | Principles, rules and decisions — read first |
| A | 1 | Foundations: math, springs, silk rope, storage, frame clock |
| B | 2 | Seeing the desktop: windows → walkable surfaces |
| B | 3 | Drawing the spider: overlay windows, vector renderer, look system |
| C | 4 | The body: modes, kinematics, gait, legs, turning |
| C | 5 | The pointer: click, drag, throw, scroll, watching |
| D | 6 | The brain: decisions, moods, the activity repertoire, personality |
| D | 7 | Air: jumping, falling, throws, landing, being covered |
| D | 8 | Silk: lines, rappel, climb, swing, mantle, hammock |
| D | 9 | Peek-a-boo |
| E | 10 | Prey, feeding, wildlife |
| E | 11 | Toys and the laser |
| E | 12 | Traces |
| E | 13 | Memory: growing up |
| F | 14 | Sensing the machine: full screen, battery, weather, music, pop-ups, lock |
| F | 15 | The box, visitors, thoughts |
| G | 16 | App shell: tray, panel, settings, Studio, My Spiders, welcome, entrance |
| H | 17 | The habitat (terrarium), in sub-stages 17a–17l |
| I | 18 | Talking spider, web-page climbing, browser extension (optional) |
| J | 19 | Packaging, updates, bug reports |
| J | 20 | Test and verification harness |
| K | — | Appendices: API mapping, settings keys, constants, risk register, source map |

---

# PART A — PRINCIPLES AND FOUNDATIONS

## Stage 0 — Read this first

### 0.1 What the product is

A single spider the user owns and designs. It lives in a transparent, click-through overlay on top of the desktop. It treats the real world of the screen — display borders, the top and sides of every open window, the taskbar — as terrain. It has a personality (six sliders plus ~30 per-behavior dials), a memory that slowly shapes it, and a vast repertoire of small animated behaviors. It can be picked up and thrown, fed, played with, kept in a box, and moved into an interactive terrarium.

The product sells **personality and physical believability**. The owner's words: personality is "the main thing this spider brings to the table"; walking looks are "the core of the whole app". Everything below should be read with that in mind: when two implementations are both correct, choose the one that reads as more alive.

### 0.2 Non-negotiable rules (from the owner)

These are binding. Each is something that was built, judged wrong, and corrected.

1. **The spider can never freeze.** The frame loop runs on one thread at 60 Hz; any spike is a visible stutter. All heavy work (sprite rasterization, tank pathfinding, surface tracing, window capture, art painting) runs off the main thread. Budget: desktop main-thread work ≈ 0.1–0.2 ms/frame, tank ≈ 0.6–0.9 ms/frame; app CPU ≈ 15% of one core active, ≈ 4% resting, ≈ 12 MB resident on the desktop.
2. **Flat window-top walking is the reference look and must not be "improved".** The owner: "the walking and standing on the top of a flat window looks good and should not be changed… it's the edge cases that are an issue" (corners, gaps, furniture, landings). Legs on flat ground use the *classic* rig (Stage 4). Fix edge cases only with changes that are no-ops on a flat edge.
3. **Do not re-engineer the legs unasked.** Two "new leg systems" were built and one was ripped out ("the new walking is just horrible… go back to the walking system used in 1.0.0"). Port the **1.0.0 classic leg system** as the default. The later optional systems (refined walk, natural walk, "legs in the round") are specified in Stage 4 as *optional extras, to be built last, behind toggles*.
4. **Everything it does is a posture reached by springs — nothing snaps.** Height, nose pitch, crouch, abdomen wag, eyelids, squash all spring toward targets. Feet *step* to new places; they never slide or teleport.
5. **Clicks pass through unless the pointer is actually on the spider** (or on a creature/toy/bubble, or while a pointer-held toy is active).
6. **Scrolling over the spider is an order, and it obeys without reversing** (Stage 8.5).
7. **One owned spider.** Other spiders are *visitors* only: random looks, no name, not customizable, not saved, opt-in, max 5.
8. **Toys are pointer-driven**, like the laser — not free-standing prey (Stage 11).
9. **Hammock rules:** windows never affect the hammock; only the pointer moved over it wakes it, and it gets up gracefully; it falls out only if the hammock is destroyed (Stage 8.8).
10. **Maximized windows count as full screen** (cinema manners) when they are the front window on their screen (Stage 14.1).
11. **Windows in front of the window it stands on hide it; it escapes at once** — but the screen rim, taskbar-equivalent, and (on macOS) menu bar are in front of everything and never hide it (Stage 7.6).
12. **Habitat shelter preference:** structures the user built beat natural cover when the spider chooses shelter, hide, rest or sleep places (Stage 17h).
13. **No survival meters, chores, or "needs".** Hunger exists only as a gentle nudge in the tank; nothing "goes wrong for going without".
14. **Welcome tour and habitat tour text is generic** — "your spider", never the user's spider name or data.
15. **Talking spider output is cute, simple, sensible — never philosophical or vague**, with an explicit on/off switch (Stage 18.1).
16. **Direct-download distribution; no store sandbox.** The app may use whatever system access it needs, including relaunching itself to update.
17. **Privacy:** geometry only. Window *titles* and *contents* are never read for anything but the opt-in web-page climbing (and then only boiled down to a number). Notification text is never read — only that a banner appeared. Nothing is sent anywhere except the optional weather lookup and opt-in bug reports.

### 0.3 Design decisions you must make before coding

| # | Decision | Recommendation |
|---|---|---|
| D1 | **Language/stack.** | Keep the behavior core (Stages 1, 2-model, 4–15, 17-model) in one portable codebase. The macOS core is Swift and compiles on Windows (type-checking all non-drawing logic against Foundation alone produced errors only in the FFT code). If you reuse it: Swift core + a thin native host (C++/Win32/Direct2D/DirectComposition, or C#) for windows, drawing, input, tray and UI. If you rewrite: any systems language; port the Swift as the specification. Either way, keep the core free of OS calls so a headless simulator can run it (Stage 20). |
| D2 | **Units and DPI.** The macOS code works in points with y-up, origin bottom-left of the primary display. | Keep the core in **y-up** coordinates (the entire geometry assumes "up" is +y, and `Seg` normals depend on it). The host converts Win32 (y-down, physical pixels) at the boundary. For mixed-DPI setups see 2.9. |
| D3 | **Drawing backend.** | A small 2D vector API matching the ~40 CoreGraphics verbs the art uses (Stage 3.2). Skia is the lowest-risk choice (identical anti-aliasing on every platform, and you can verify against macOS output). Direct2D is acceptable. |
| D4 | **Overlay composition.** | DirectComposition + a premultiplied-alpha swap chain per overlay window, or `UpdateLayeredWindow` with a 32-bit DIB for the small sprite window. (3.1) |
| D5 | **UI toolkit** for panel, Studio, habitat toolbar, decorate panel, tours. | Choose one toolkit and stay in it (WinUI 3, Qt, or custom-drawn). The Mac UI is ~7k lines of AppKit; none of it carries over. |
| D6 | **Talking spider** backend. | Apple Intelligence has no Windows equivalent. Options: Windows AI (Phi Silica, Copilot+ only), a bundled small local model, or a cloud API. Ship without it first; the prompt rules in 18.1 carry over to any model. |
| D7 | **Menu bar / notch / widgets / Spaces.** | None exist on Windows. See the "no equivalent" table in 2.8. |

### 0.4 Glossary

- **Surface / loop / seg** — a walkable polyline (loop) made of straight segments (segs); the spider's body origin follows a path *offset from the real edge* by the body height ("standoff").
- **Standoff** — the distance between the walking path and the real edge: `22 × scale` world units. Feet land on the edge itself; the body rides above it.
- **Anchor** — (loop id, segment index, t along segment, direction) — "where it is standing".
- **Pose** — the complete drawable state of the spider for one frame (the `SpiderPose` struct, 3.5).
- **Look** — the saved appearance (body, face, hats, coat…); **Design** — look + personality + gait + habits + name + thoughts.
- **Profile / yaw / facing** — the spider is drawn side-on (profile) and turns by sweeping through a front view; `facing` is ±1 (which way along the ledge), `yaw` runs +1 → 0 → −1 during a turn.
- **Posture** — the set of spring-driven body values (lift, pitch, crouch, wag, stretch…) an activity targets.
- **Tank / habitat** — the terrarium window and its simulated world (Stage 17).
- **Cinema** — the manners used when a full-screen video has the display (14.1).
- **Calm** — a throttle that skips frames when nothing visible has changed (1.7).

### 0.5 Conventions used below

- All distances are **world units** (macOS points) at `scale = 1` unless stated. A spider's overall length is ≈ 46 units; its sprite draw radius is 72 units.
- Scales (the Size setting): Tiny 0.62, Small 0.78, Medium 0.95, Large 1.2, Chonky 1.55. The owner's spider is Small (0.78). **Validate every walking/leg change at all five sizes.**
- `dt` is seconds. The spider's per-frame update clamps dt to ≤ 1/30 s.
- `chance(p)` is `random(0…1) < p`; `randRange(lo, hi)` returns lo if hi is NaN etc. (never traps on reversed bounds).
- "Weights" are draw weights in a weighted random pick; a **habit dial** (0…1) multiplies a weight via `Habits.weight` (1.3).

---

## Stage 1 — Foundations

### Goal
A portable core library with math, springs, the silk-rope solver, a storage layer, and a frame clock — plus a headless test runner that can step it. No windows yet.

### 1.1 Project shape

```
core/        pure logic: no OS calls, no drawing-API calls except through the Draw shim interface
  Math, Surfaces, Spider, SpiderDesign, Memory, Prey, Toys, Traces, Weather, Habitat*, Beat, PageLedges
renderer/    vector drawing of the spider and the habitat art, against the Draw shim
platform/    windows, input, screens, tray, audio, power, capture, storage paths, updater
app/         UI: tray menu, panel, Studio, habitat window, tours
tools/       headless simulator, film/sheet renderers, A/B harnesses
```

The macOS build keeps tool builds working by listing source files explicitly; do the equivalent with a library target the tools link against. **Rule:** `core/` must not call OS APIs. The macOS code violates this in a few places (`NSScreen.main`, `NSWorkspace`, `UserDefaults`, `CACurrentMediaTime`, `CGPath`); the port should route all of them through small interfaces (`Screens`, `Clock`, `Settings`, `Geometry`).

### 1.2 Vectors and helpers

`V2 {x, y}` with `+ − * /`, `dot`, `cross` (2D scalar), `length`, `lengthSquared`, `normalized`, `rotated(by:)`, `angle` (atan2), `distance(to:)`, `lerp`. `V3 {x, y, z}` (only needed by the optional "legs in the round" system). Helpers:

- `clamp(v, lo, hi)`; `lerp(a, b, t)`; `approach(value, target, rate, dt)` = exponential approach `value + (target−value)(1−e^(−rate·dt))`.
- `angleDelta(from, to)` = shortest signed difference wrapped to (−π, π].
- `smoothstep(t)` = clamp t to 0…1, `t²(3−2t)`.
- `easeOutCubic`, `easeInOutSine`, `easeOutBack(t, overshoot=1.7)`.
- `projectOnSegment(p, a, b)` → (distance along segment, perpendicular distance), t clamped to [0,1].

### 1.3 Springs (used for every soft motion)

```
Spring { value, velocity, stiffness (k), damping (c) }
step(to target, dt):   a = (target − value)·k − velocity·c
                       velocity += a·dt;  value += velocity·dt        // semi-implicit Euler
nudge(v): velocity += v        reset(v): value = v, velocity = 0
Spring2: the same with V2 value/velocity.
```
Defaults `k = 180, c = 18`. Stable at 60 Hz because dt is clamped. The master list of spring constants is in 4.2.

**Wobble** (cheap smooth 1-D noise for idle jitter): `value(t) = 0.6 sin(x) + 0.3 sin(1.87x + 1.3) + 0.1 sin(4.31x + 2.7)` where `x = t·freq + seed·37.13`. Each leg owns a Wobble (`seed = i·2.7`, `freq = 1.1 + (i%4)·0.17`).

### 1.4 Silk rope

Every thread in the product (dragline, swing line, traces, hammock strands, toy tow-lines) is the same solver: a **Verlet chain of 14 segments (15 points)**.

```
state: points[0…14], prev[], length (rest length of the whole rope), headPinned, tailPinned, live
reset(from a, to b): points lerp a→b; length = |a−b|; both ends pinned
reset(along polyline): resample evenly to 15 points at rest; length = path length
step(head, tail, gravity, drag, wind, dt):
    acc += min(dt, 0.05); fixed substep h = 1/120 s; at most 6 substeps per call
    each substep:
        pin ends: points[0] = head (if headPinned); points[n] = tail (if tailPinned)
        integrate free points:  v = (p − prev)·drag;  prev = p;  p += v + (0,−gravity + wind)·h²
        rest = length / n
        taut = tailPinned && |points[0] − points[n]| > length·0.96
        straighten = taut ? 0.16 : 0.05
        10 Gauss–Seidel passes, alternating direction:
            relax each link: if dist > rest, pull the two points together by the excess
               (only resists stretching — never pushes apart; if one end is pinned, move only the other)
            each interior point drifts toward the midpoint of its neighbours by `straighten`
    after substeps, re-pin both ends exactly
push(i, by d): displace point i (not a pinned end) — used by the pointer brushing a strand
motion: the largest per-substep movement of any point (≈0 when at rest — used to sleep the solver)
```
Behavior this must give: sags when slack, lags and whips when fired or swung on, bows when the spider bounces on the end, drifts down from its anchor when released while fading.

### 1.5 Storage

- A **settings store**: typed key/value, JSON on disk (`%APPDATA%\SpiderBuddy\settings.json`), written atomically, tolerant on read (unknown keys ignored, missing keys defaulted — older saved designs must keep loading). The master key list is Appendix B.
- **File stores**: `Spiders/` (one JSON per saved spider), `Habitats/` (one JSON per saved habitat; `.spiderhabitat` is the share format), `memory`, `habitatKnowledge`, `habitatWeatherNow`. All under the app-data folder, overridable by environment variables for tests (`SPIDER_LIBRARY`, `SPIDER_HABITAT_LIBRARY`).
- **Tolerant decoding is a hard requirement** for the dial struct `Habits`: a new dial must default when absent in old saves, otherwise every older design silently resets.
- Unknown keys must round-trip harmlessly (e.g. old `continuity`, `newLegs` keys are simply ignored).

### 1.6 Randomness

All behavior uses ordinary randomness. The test harness needs **seedable** RNG injection for A/B comparison (macOS tools use seeded runs and `SWIFT_DETERMINISTIC_HASHING=1` because dictionary iteration order otherwise varies per process — avoid depending on hash iteration order in decisions, or the A/B harness will be flaky).

### 1.7 Frame clock

- One master clock at **60 Hz** tied to the display (Windows: a `DwmFlush`-paced loop or a waitable timer synced to the monitor; do not run 120/144 Hz — gating a high-rate clock by elapsed time produced alternating 16/25 ms steps that read as stutter). Ask for exactly 60.
- `dt = clamp(now − last, 1/240, 1/20)` at the app level; the spider's update clamps again to ≤ 1/30.
- **Low Power** → 30 Hz clock.
- **Calm throttle:** when nothing visible changed for ~1 s, skip frames (run one of every 3; one of every 2 in low power or when only critters are astir). Anything on the pointer (a held toy, the laser) or any pointer movement > 0.4 units cancels calm immediately.
- All visible changes for a frame are committed **once**, at the end of the tick (one composition transaction per tick). A second mid-tick commit doubled the cost on macOS.
- Housekeeping inside the tick: every 30 ticks (0.5 s) — pending permission nudges, rain check, music-listening check, wake-from-dormant safety; every 3600 ticks (60 s) — save memory if dirty; at 1800 mod 3600 — save habitat knowledge if dirty (never during habitat tests).

### Done when (Stage 1)
- A headless program can construct the math library, step a `SilkRope` pinned at the top with a free weight, and print positions showing: slack sag, taut straightness, a swing with lag.
- Springs reproduce critically-damped-ish settling (k=180, c=18 settles in ≈0.5 s with slight overshoot).
- Settings round-trip, including a file with extra and missing keys.

---

# PART B — THE DESKTOP AND THE SPIDER'S SIGHT

## Stage 2 — Seeing the desktop: windows → walkable surfaces

### Goal
Given the live desktop, the core holds a `SurfaceMap`: a set of polylines the spider can walk on, kept current as windows move, resize, open, close, minimize and get covered. You can verify it with an on-screen debug overlay drawing the loops, before any spider exists.

### 2.1 The window tracker

**Purpose.** Poll the window system for on-screen window rectangles. *Only geometry is read.* Titles are read only by the opt-in web-page climber.

**Output per update** (`onUpdate`): the list of `TrackedWindow`, the list of full-screen display rects, the list of dock/taskbar strips, and the list of "taken" windows.

```
TrackedWindow {
    id,                      // OS window handle
    frame,                   // y-up global coords (origin bottom-left of the primary display)
    depth,                   // front-to-back order, 0 = frontmost
    owner,                   // process/app name
    cornerRadius,            // default 26 (macOS); measured per window where possible
    pid, bundleID,           // app identity (browser detection)
    titleHash?,              // browsers only, opt-in, a number — never the title
    maximized,               // fills its screen below the menu bar (2.5)
    widget                   // macOS desktop widget (no Windows equivalent)
}
```

**Polling rate.** 30 Hz while any window is moving; 10 Hz when the desktop is still. (On Windows prefer `SetWinEventHook` for `EVENT_OBJECT_LOCATIONCHANGE`, `EVENT_SYSTEM_MINIMIZESTART/END`, `EVENT_OBJECT_CREATE/DESTROY/SHOW/HIDE`, and `EVENT_SYSTEM_FOREGROUND`, plus a 10 Hz sanity poll.) The poll runs on a background queue; results are handed to the main thread.

**Which windows count as furniture** (all must hold):

1. Ordinary app window: normal layer (macOS layer 0). Windows: visible, not minimized, not cloaked (`DWMWA_CLOAKED == 0`, which also excludes UWP ghost frames and windows on other virtual desktops), not `WS_EX_TOOLWINDOW`, not `WS_EX_NOACTIVATE` shell surfaces, not owned by the shell (Progman/WorkerW/Shell_TrayWnd/Start menu/search/Notification area), owner not in the ignored list.
2. Width > 130 and height > 90 (smaller things are decoration).
3. Alpha ≥ 0.35 (nearly-transparent windows are skipped).
4. Owner is a regular app (macOS: `activationPolicy == .regular`).
5. Up to **28** windows are kept, front to back.
6. Our own windows are skipped, *except* the Studio and the habitat window, which are furniture like any other.

**Ignored owners (macOS):** Window Server, Dock, SystemUIServer, Control Center, Notification Center, Spotlight, DesktopSpider, Wallpaper, TextInputMenuAgent, universalaccessd, coreautha, loginwindow. Windows equivalent: `explorer.exe` shell windows (taskbar, desktop, flyouts), `SearchHost`, `StartMenuExperienceHost`, `ShellExperienceHost`, `TextInputHost`, `LockApp`, and the app itself.

**Bounds.** Use the **visible** frame, not the invisible resize border: `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)`. `GetWindowRect` includes ~7 px of invisible border on Windows 10/11 and would float the spider above the window.

**Corner radius.** macOS windows round from ≈16 to >30 pt (26 default; 38 is the *spider's* cornering constant). Windows 11 windows are ≈8 px; Windows 10 and maximized windows are 0. Read `DWMWA_WINDOW_CORNER_PREFERENCE` or measure from a capture; the model needs a per-window radius clamped to `min(w/2, h/2)`.

**Minimizing = drop at once.** A window heading into the Dock (Scale or Genie animation) keeps being listed with its animated bounding box; the macOS tracker detects "size changed, no corner kept, middle and far edge heading for the Dock side" and drops the window from the map immediately (and holds it dropped until it leaves the list or sits still 0.6 s). On Windows, `EVENT_SYSTEM_MINIMIZESTART` fires first — remove the window on that event. Also hide windows on `EVENT_OBJECT_HIDE`/cloak at once.

**Full-screen detection** (per display):
- A window covering a display whole (within 2 pt inset, or ≥98% width and ≥90% height when no desktop is showing) is an **exclusive full-screen app**: it is not furniture; the display goes to *cinema* (Stage 14.1). Windows: `SHQueryUserNotificationState` (`QUNS_RUNNING_D3D_FULL_SCREEN`, `QUNS_BUSY`, `QUNS_PRESENTATION_MODE`), plus "window rect == monitor rect and no caption/WS_THICKFRAME".
- Displays "with a desktop showing" are those that have wallpaper/desktop windows covering them; a display without one is in a full-screen Space.
- `bareScreens`: displays with no desktop showing (a full-screen Space with, e.g., a browser whose bars are a separate window).

**Notification banners.** Each banner is a separate Notification-Center window as big as its display, above ordinary windows, ~4 s. The tracker reports `onBanner(screen)` when a new one appears (not for one already showing at launch). **Never read banner text.** Windows toasts: detect the shell toast host window appearing (a probe is required — class names change between builds); do not use `UserNotificationListener` (it reads content and needs permission).

**macOS desktop widgets** are windows at layer −2147483601 from Notification Center, inset 8 pt, ~26 pt corners, max 16 listed, treated as furniture behind every window; setting "Stand on Widgets" (default on). Windows has no equivalent (see 2.8).

### 2.2 Furniture geometry facts

- A window's top is a *shelf* to stand on; sides are walls to cling to; bottom is a ceiling to hang from.
- **Occlusion:** each window has `depth`. A window loop is blocked where windows with smaller depth (in front) cover it.
- Everything lives in y-up global coordinates. Convert Win32 y-down: `y_up = primaryTop − y_down`.

### 2.3 The surface model

```
enum SurfaceKind { screenBorder, windowEdge, dock, menuBar, webLedge }
   appeal (how much it likes to jump here): screenBorder 1.0, windowEdge 1.7, dock 1.35, menuBar 1.25, webLedge 1.6
   onWindow = windowEdge || webLedge        // can be covered by a window in front

enum EdgeFacing { up, down, left, right }   normals (0,1) (0,−1) (−1,0) (1,0)

Seg { a, b, facing, dir, len, blocked: [(lo, hi)] }
    init orders endpoints so that normal == dir rotated +90° (CCW). If not, SWAP a and b.
    This guarantees the sprite frame (+x along the edge, +y along the outward normal) is never upside down.
    point(t) = a + dir·clamp(t, 0, len)
    limit(from t, dir) = how far you can walk before a blocked stretch or the end
    block(range): add a covered t-range; keep sorted and merged
    span(inside rect): Liang–Barsky t-range inside a rect

SurfaceLoop { id, kind, segs (the BODY path), edge (the real edge, where feet go),
              closed, depth, rect, cornerRadius, owners[] (habitat: thing id per seg) }
SurfaceJunction { from loop id, fromVertex, to loop id, toVertex, at }   // habitat: walk from one loop to another
Anchor { loopID, segIdx, t, dir(+1 toward seg.b, −1 toward seg.a) }
```

**Standoff** = `22 × scale`. Loops store the *body-origin* line (edge offset by standoff) plus the real `edge` for feet. `SurfaceMap.standoff` is set from the size setting (`standoff(for: scale) = −SpiderRenderer.ground × scale`, ground = −22).

### 2.4 `SurfaceMap.rebuild(...)` — what loops are made

Input: windows, cinema displays, zoomed displays, dock strips, optional page loops. Output: loops, byID, occluders (front-to-back rects), worldBounds, screenFrames, dockRects.

**Per display** (index i):

1. If the display is in *cinema* → only the cinema loops (14.1) and nothing else for that display.
2. `r = frame.insetBy(standoff)`; skip if ≤ 60 in either dimension.
3. **Menu bar present** (`menuBarHeight = frame.maxY − visibleFrame.maxY > 12`): the screen border is an **open U** — down the left wall, along the floor, up the right wall — with the walls stopping at `wallTop = visibleFrame.maxY − standoff − 6`. (The very top edge is under the menu bar where the spider cannot be seen; walking there made it vanish.) `edge` = left wall, floor edge, right wall.
   **No menu bar** (Windows): closed rectangle loop: floor (left→right, facing up), right wall (facing left), ceiling (right→left, facing down), left wall (facing right). On Windows use the **work area** (screen minus taskbar) for the floor — see 2.8.
4. **Menu bar loop** (macOS only): one open seg along `y = visibleFrame.maxY − standoff`, from `frame.minX + 90` to `frame.maxX − 90` (clear of notch/status items), facing **down** (the spider hangs from the bar's lower lip), min length 100, depth −20, `kind = menuBar`. Its edge is the lip itself.
5. **Floor with a dock** (`floor(of:standoff:dock:)`): if a Dock strip sits on the bottom of this screen, not spanning it (inset > 40 each side, height < screen/3): the floor goes **up and over** it — floor segs: `(x0→lx)`, up the dock's left side facing left, across the dock top facing up, down the right side facing right, `(rx→x1)`; where `lx = d.minX − off`, `rx = d.maxX + off`, `top = d.maxY + off`. Other-edge docks get their own loop: one seg along the top (`y = dock.maxY + off`, inset 6, min length 60, facing up, kind `dock`, depth −10).
   - If the Dock is auto-hidden there is nothing to walk on except during the moment it slides in.

**Per window** (not in cinema, > 130×90, not `maximized`-behind-another):

```
o = rect.insetBy(−standoff)           // grown outward by the standoff
segs = [ top (tl→tr, up), right (tr→br, right), bottom (br→bl, down), left (bl→tl, left) ]   // clockwise, normals outward
loop = SurfaceLoop(id "win:<id>", kind windowEdge, closed true, depth, rect)
loop.edge = rectEdge(rect, inside: false)
loop.cornerRadius = min(window.cornerRadius, w/2, h/2)
```
So it walks the top like a shelf, rounds the corner down the side, and hangs beneath the bottom.

A **maximized** window that has another window in front of it gets **no loop** (its edges are the screen's), though it still occludes.

**Blocks.** For every window loop, for every window in front (smaller depth), grow that window's rect by `standoff × 1.4` and `block()` each seg's span inside it. Screen borders, menu bar and dock are *never* blocked — the spider is drawn above every window and walks the rim across whatever overlaps it.

**Confinement box.** `confine: CGRect?` clips every loop to the box with Liang–Barsky; segments with < 8 units left are dropped; surviving runs of connected pieces become open loops named `"<id>~k"`; closed loops' first/last runs re-join. Junction tables are discarded when clipped. (The Box feature, 15.1.)

`generation` increments on every re-lay-out — anything computed from the loops (the tank's pathfinding) caches by generation.

### 2.5 `resolve(anchor, cornerRadius)` — a position on the surface

Given an `Anchor`, return `SurfacePoint { pos, tangent, normal, … }`. Straight parts are simply `seg.point(t)`. Near a corner between two segs the body path is **rounded**:
- Outside corners of **rounded windows** use an arc of radius `windowCornerRadius + standoff` about the window's corner-centre (`windowCornerArc`/`roundCorner`). (A quadratic that ignored the window's real radius lifted the body to 1.6× standoff.)
- Every other corner uses a quadratic Bézier round-off with reach computed from `Spider.cornerRadius = 38 × scale`.
- Flat segments must be unaffected: flat-walk output must be identical with and without corner handling.

`SurfaceLoop.onRoundedCorner(p)` projects a point on the square outline onto the rounded corner (returns the point and outward normal) — used to keep *feet* on the real curved edge. `snapToEdge(p, loopID)` returns the nearest point on the true edge (wrapping onto the next side around a corner).

### 2.6 Queries the spider needs

Implement these on `SurfaceMap`; the brain uses all of them.

- `loop(id)`, `seg(anchor)`, `worldPoint(anchor)`.
- `isVisible(p, depth)` — not hidden by a window in front. `isClear(p, depth, margin)` — clear of windows in front by a margin. `canHold(loop, seg, at t)` — whether a line may fasten here (never to a covered stretch).
- `sampleSpots(spacing = 34, visibleOnly)` → candidate standing spots across all loops, each with anchor, point, loop, seg. `nearestSpot(to:within:excluding:)`.
- `ceiling(above p, maxRise = 900)` → the first down-facing edge above (for lines); `landingBelow(p, halfWidth = 24)` → height of the first thing under p; `depth(at:)`; `bounds(around:)`; `isOnScreen(p, slack)`; `screenFrame(containing:)`; `menuBarBottom(for:)`.
- `isCinema(p)`; `junctions(from:at:)`; `owner(of:)`.
- `habitatCopy()` — a copy for background pathfinding.

### 2.7 Special display states

**Cinema** (a display taken by an exclusive full-screen app or a front maximized window): only a floor and a ceiling exist, no walls/menu bar/dock/windows. Built by `cinemaLoops(id, frame: stage, standoff)`; the `stage` rect is the display, except:
- a **zoomed (maximized)** window: the ceiling is the menu bar's lower lip (`visibleFrame.maxY`), and the floor is a shown Dock's top (keep back > 20);
- **notched** full screen: ceiling drops to the lower lip of the camera-housing strip (`safeAreaInsets.top`).
Hold-off: `cinemaScreens`/`zoomedScreens` use a 4-poll hysteresis so a flicker does not toggle manners.

**Dock/taskbar detection (macOS):** a Dock that stays put keeps its edge out of `visibleFrame` (>20 pt gap on bottom/left/right). Its exact frame is read by Accessibility if allowed, else estimated from tile counts. On Windows read `SHAppBarMessage(ABM_GETTASKBARPOS)` and `ABM_GETSTATE` (auto-hide) — easier and exact.

### 2.8 Mac-only things and their Windows treatment

| macOS | Windows treatment |
|---|---|
| Menu bar (hang from its lip) | No bar. Option: treat the **top edge of the work area** as a ceiling (closed-rectangle branch of 2.4.3). Skip the notch inset. |
| Dock (short strip on the floor) | Taskbar is a full-width strip. Treat the **work area** as the screen: floor = top of the taskbar. The spider is then standing on the taskbar. If you want a "walks over the Dock" feel, a centered Win11 taskbar's icon region is not a separate window — do not try. |
| Notch / `safeAreaInsets` | Not needed. |
| Full-screen Spaces | Borderless full-screen windows and exclusive D3D; use `SHQueryUserNotificationState` and rect tests. |
| Mission Control, Spaces | Virtual desktops: windows on other desktops are cloaked → not listed. The overlay must appear on all desktops (set via `IVirtualDesktopManager`/pin or by creating per-desktop; `WS_EX_TOOLWINDOW` overlays show on all desktops only if pinned — test). |
| Desktop widgets | None. Optionally treat desktop icons' rows as furniture (not recommended for v1). |
| Genie/Scale minimize | Drop on `MINIMIZESTART`. |
| Notch & menu-bar see-through quirks | Not applicable. |
| Screen Recording permission | Not needed for BitBlt/PrintWindow; Windows.Graphics.Capture shows a yellow border unless the capture capability is declared. |

### 2.9 DPI and multiple monitors

The macOS code assumes one coordinate space in points where each display has its own frame. Windows monitors can have different DPI.
- Make the process Per-Monitor-V2 DPI aware.
- **Recommended:** the world is **physical pixels** of the virtual desktop. Define `unitsPerPoint(monitor) = dpi/96`. The spider's effective `scale` while attached to a surface on a monitor is `userScale × unitsPerPoint(monitor)`, re-evaluated on landing (not mid-air). Standoff/size constants scale with it.
- The overlay windows are created per monitor or as one virtual-desktop-sized window per layer; per-monitor is simpler for DComp.
- Leaps between monitors: loops exist per monitor; a jump whose target is on another display simply flies across the virtual desktop — avoid if the monitors' DPI differ by more than 25% (the size change would show).

### 2.10 Acceptance: draw it

Write a debug overlay that draws, over the real desktop: every loop's `segs` in blue, `edge` in green, blocked stretches in red, junction points, screen/taskbar/dock rects. Drag windows around, open/close/minimize/maximize, go full-screen on a video, plug a second monitor.

### Done when (Stage 2)
- Loops follow windows live at 30 Hz with no drift; a minimized window vanishes instantly.
- A window dragged in front of another blocks exactly the covered stretches (plus the 1.4×standoff grow).
- A maximized front window produces cinema loops (floor + ceiling only); with a second window in front of it, it produces no loop but still occludes.
- A synthetic desktop (fake windows, no OS) feeds the same `rebuild` for headless tests; the sim in Stage 20 uses it.


---

## Stage 3 — Drawing the spider

### Goal
A static, correct, beautiful spider drawn in a transparent window you can move around by hand, plus a contact sheet of every pose and option. No behavior yet.

### 3.1 Overlay window architecture

The macOS app uses **several separate transparent, always-on-top, click-through windows** because each has a different size and update cost. Reproduce the split; compositing a screen-sized transparent window every frame cost more than the entire rest of the app (≈ 26% CPU in an earlier build).

| Window | Size | Content | Notes |
|---|---|---|---|
| **Sprite window** | `spriteSide + 68` square, where `spriteSide = max(100, round(72·2·scale))` (draw radius 72) | The spider only | **Follows the spider.** Re-centered on it when it drifts `68/2 − 4` units from center. Its layer content only changes when the spider's *shape* changes; position changes are free. |
| **Silk window** | One per display (or the virtual desktop) | Dragline, swing line, hammock strands, held threads | Screen-sized, so **order it out (hide) whenever no thread is out.** |
| **Prey/toy window** | Screen-sized | Creatures, toys, the laser dot | Shown only while something is out (`preyShown`). |
| **Traces window** | Screen-sized | Silk strands, webs, leftovers | Under the spider; shown only while traces exist. |
| **Hammock window** | Small, around the corner | The sling | *Above* the spider so a sleeping spider is seen through the silk. |
| **Hand-catcher window** | Pointer-sized | Rides under the pointer while a toy/laser is in hand; swallows the click that deploys it | Hidden over the spider so it can still be picked up. |
| **Box-draw window** | Per screen | Dims the desktop, takes a drag to draw the box | Higher level, takes mouse. |
| **Visitor windows** | One sprite window each | Visitors | Max 5. |
| **Habitat window** | Resizable | The terrarium (Stage 17) | An ordinary window — *furniture* to the tracker. |

**Window attributes (macOS → Windows).**
- Borderless, non-activating, never key/main, no shadow, transparent (`isOpaque = false`, clear background), no animation. → `WS_POPUP`, `WS_EX_LAYERED`, `WS_EX_TOPMOST`, `WS_EX_NOACTIVATE`, `WS_EX_TOOLWINDOW`, plus `WS_EX_TRANSPARENT` while click-through.
- All Spaces, stationary, full-screen auxiliary, ignores cycle → visible on all virtual desktops and over full-screen apps where possible; excluded from Alt-Tab (`WS_EX_TOOLWINDOW`).
- **Level:** above every app window, **below** open menus. macOS: above the menu bar and Dock but below menus ("draws above the menu bar and the Dock but below open menus, so it can hang in front of the clock without ever swallowing a menu click"). Windows: `HWND_TOPMOST`; accept it may sit over or under the taskbar depending on z-fighting — test with the Start menu open (it must stay above the overlay or at least never lose clicks).
- Mac frame is never nudged: the window must be placed exactly where asked (macOS nudges windows down out of the menu bar strip; override `constrainFrameRect`).
- **Colour:** draw in sRGB, 8-bit premultiplied BGRA. On macOS, sRGB bitmaps in Display-P3 windows forced a copy every commit — mark the overlay windows as sRGB. On Windows use a BGRA premultiplied swap chain/DIB, `DXGI_ALPHA_MODE_PREMULTIPLIED`.

**Click-through and hit-testing.** Whether clicks reach the app is decided **every tick** (a stale decision = a spider you can't pick up):
```
wantsMouse = interactive && ( spider.isHeld || (!inHabitat && (spider.hitTest(cursor) || thoughtBubbleUnder(cursor))) )
sprite window ignoresMouseEvents = !wantsMouse
for each visitor: wants = interactive && (v.held || v.hitTest(cursor))
prey window takes mouse only if: interactive && preyShown && (a creature is held || a creature/toy is under the pointer and the spider isn't)
```
`spider.hitTest(p)`: within `grabRadius = 30 × scale` of the body (plus the bubble when a thought/chat bubble is up). "Click to Pick Up" off ⇒ everything click-through, always. On Windows toggle `WS_EX_TRANSPARENT` (or answer `WM_NCHITTEST` with `HTTRANSPARENT`) — both flip instantly with `SetWindowLong`.

**Peek-a-boo occlusion.** The spider is drawn above all windows, but whatever of it falls *inside a window in front of the window it stands on* is cut out (`pose.hiddenBy: [rect]`). Apply as clip rectangles (even-odd exclusion) when rasterising the sprite. The screen rim, taskbar and menu bar are glass in front of everything: they never cover it, "however far a window reaches toward the edge" (a Preview window taller than the screen used to hide it on the floor). Two special draws: `peekGrip` (two front feet drawn as dots, ignoring the clip, gripping the edge it's behind) and the first-entrance clip under the see-through macOS menu bar (not needed on Windows).

### 3.2 The drawing shim

The art is ≈ 15.5k lines of procedural vector drawing against a Core Graphics-style context. The vocabulary actually used (counts from the source; every one must exist in your shim):

| Verb | Count | Notes |
|---|---|---|
| `setFillColor`, `setStrokeColor`, `setLineWidth` | 468 / 344 / 362 | Colours are RGBA floats 0…1 |
| `move`, `addLine`, `addQuadCurve`, `addCurve`, `addArc`, `closeSubpath` | 330 / 305 / 112 / 22 / 15 / 34 | Path building |
| `addEllipse`, `addRect`, `addLines` | 39 / 6 / 6 | |
| `fillEllipse`, `strokeEllipse` | 262 / 57 | |
| `addPath`, `fillPath`, `strokePath`, `drawPath`, `fill`, `stroke` | 191 / 92 / 304 / 27 / 129 / 8 | `drawPath` takes fill/stroke/both modes |
| `saveGState`, `restoreGState` | 168 / 168 | Full state stack (CTM, clip, colours, line style, alpha, blend) |
| `translateBy`, `rotate`, `scaleBy`, `concatenate` | 69 / 41 / 37 / 2 | CTM |
| `clip` (to path/rect) | 95 | Include even-odd clip (`clip(using: .evenOdd)`) |
| `setLineCap` (butt/round/square), `setLineJoin` (miter/round/bevel) | 57 / 23 | Also miter limit |
| `setAlpha`, `setBlendMode` (3 uses), `setShadow` (2), `beginTransparencyLayer`/`end` (2) | | Group opacity needed for ghosted layers |
| `drawLinearGradient`, `drawRadialGradient` | 5 / 3 | Coats, glass, sun |
| bitmap context → image | | Sprite is rasterised into an image and shown as a layer |
| text | a few | Name tag, thought-bubble text (CoreText line layout) |

Plus path *queries*: `contains(point)` (winding and even-odd), `boundingBox`, `union`, `normalized`, `intersects`, `copy(using: transform)`, `apply(block)` — used by habitat geometry (17c), where a polygon library (Clipper2) is the right replacement.

**Rule for drawing code:** all art is written in **body-local units** (see 3.4), then transformed once. Keep it that way — it makes hats, markings and weather ride through corners, rolls and hanging upside down for free.

### 3.3 Rasterising the sprite (performance-critical)

- The sprite is drawn into an **8-bit sRGB bitmap off the main thread** (serial queue, user-interactive QoS). The pose (position + image) is applied on the main thread **together**: where the layer is, what's drawn on it, the window moved to it and its silk all go up in one commit. A pose never goes up without its own picture. If drawing falls behind, only the newest pose waits; the main thread never waits.
- **Redraw only when the spider's shape changes.** `shapeDelta` compares everything that affects the drawing (legs, facing, heading, ball, bodyPitch, headTilt, headCock, headTurn, abdomenTilt, wink, palps, blink, happy, emote, thought, weather coat, outfit time for animated coats…). Position alone is free. A standing/asleep spider redraws almost never. The earlier cheaper threshold silently dropped frames while walking — every visible change must redraw.
- Animated coats (living coats, shimmering custom gradients) redraw steadily even while still.
- Sprite image is shown at its own size, centered, never stretched; contentsScale = display scale. No implicit animations on any property.
- **Draw-radius check:** a tool measures the furthest drawn pixel from the body centre across every pose and angle and asserts `drawRadius (72)` covers it. Re-run after changing art or splay/stretch extremes — sprite size is a direct CPU cost.
- Budget: one rendered frame is timed with a bench tool (Stage 20).

### 3.4 Body-local coordinates and anatomy

**Frame.** +x is the way it faces (forward), +y is its left/up (away from the ledge). One unit = one point at scale 1. Body length ≈ 46 units. `SpiderRenderer.ground = −22`: feet reach down to y = −22. (Hence standoff = 22.) The sprite frame on a surface is built from the segment: +x along the edge, +y along its outward normal (Seg's ordering rule guarantees this).

**Key constants.**
```
ground      = −22
leanPivot   = (1, −8)            // what a body lean (pitch) rotates about: between the hips
abdomen     = centre (−14, 3), rx 14, ry 13
head        = centre (9.5, 0.5), r 13
neck        = (−2, 0)
ballCentre  = (−6, −5)           // where a balled-up spider's lump centre sits
frontAbdomen= centre (0, 7), rx 13.5, ry 12.5      // front view
frontHead   = centre (0, −1), r 13
drawRadius  = 72
```
**Eyes (profile; the face is turned 3/4 so all four front eyes show):** `(centre, radius, big)`:
`(16.2, 1.2) r4.7 big` near anterior-median · `(10.0, 3.6) r3.8 big` far anterior-median · `(19.6, 6.4) r2.5` near lateral · `(5.6, 7.0) r2.1` far lateral.
**Eyes (front):** `(4.8, 0.2) r4.5 big` · `(−4.8, 0.2) r4.5 big` · `(11.6, 1.4) r2.9` · `(−11.6, 1.4) r2.9`.

**Palette (reference art):** outline `(0.298, 0.180, 0.086)`; body fill `(0.878, 0.604, 0.333)`; body light `(0.945, 0.729, 0.486)`; head `(0.898, 0.655, 0.392)`; leg fill `(0.788, 0.518, 0.278)`; leg light `(0.855, 0.596, 0.345)`; **far-side leg** `(0.690, 0.435, 0.220)`; far outline `(0.255, 0.150, 0.070)`; eye dark `(0.239, 0.129, 0.055)`; white. Far-side legs and body parts sit in shadow and are drawn a shade darker. Palettes derive from the Look; still palettes are cached (≤ 64 entries, guarded by a lock because the sprite is drawn off-thread while the main thread may draw too); living coats recompute every frame.

**Legs (classic rig — the 1.0.0 reference).** Eight legs; indices 0–3 are the **near side** (drawn in front of the body) front→back; 4–7 are the **far side** (behind the body, darker) front→back. Each leg is hip → knee → foot (thigh + shin), foot on `ground`.

Profile (side-on):
```
near 0: hip ( 9,−9) knee ( 24, 2) foot ( 30, g)   reaches ahead of the face
near 1: hip ( 6,−10) knee ( 15,−8) foot ( 18, g)   short, tucked under the chin
near 2: hip ( 1,−10) knee ( −6,−5) foot ( −6, g)
near 3: hip (−3,−9) knee (−17,−1) foot (−24, g)
far 4 : hip ( 7,−7) knee ( 21, 5) foot ( 26, g)
far 5 : hip ( 4,−8) knee ( 11, 1) foot ( 13, g)
far 6 : hip (−1,−8) knee (−11, 2) foot (−13, g)
far 7 : hip (−5,−7) knee (−21, 3) foot (−30, g)           (g = ground = −22)
```
Front view (facing you):
```
0: hip ( 8,−8) knee ( 31,−4) foot ( 38, g)    4: hip ( 8,−8) knee ( 25,−1) foot ( 31, g)
1: hip ( 7,−9) knee ( 18, 0) foot ( 22, g)    5: hip ( 5,−9) knee ( 11,−3) foot ( 14, g)
2: hip (−5,−9) knee (−11,−3) foot (−14, g)    6: hip (−7,−9) knee (−18, 0) foot (−22, g)
3: hip (−8,−8) knee (−25,−1) foot (−31, g)    7: hip (−8,−8) knee (−31,−4) foot (−38, g)
```
Rig at a given `profile` (1 = side-on, 0 = facing you) = linear blend of the two tables. **Leg styles** change `reach` (multiplies foot-x and knee offset from the hip), `knee` (extra knee rise) and `width`; the feet stay on the ledge, so long legs stand wider with higher knees.

**Knee model (classic — "art, not IK").** `knee(leg, hip, foot, lift, profile)`: take the rest knee offset from the hip, **rotate it by the angle the hip→foot vector has swung from rest**, scale by `reach = clamp(|hip→foot| / restLen, 0.5, 1.3)`. If `reach < 1` (foot closer than rest) the leg *folds*: thigh `a` and shin `b` keep their lengths, `d = clamp(dist, |a−b|+0.5, a+b−0.5)`, `x = (a²−b²+d²)/(2d)`, `h = √(a²−x²)`, knee at `hip + dir·x ± perp·h` on the rest knee's side. The solver is deliberately *not* IK: a two-bone solver picks a different elbow side as the foot crosses the body and the legs stop looking like one animal. The one exception is a leg gripping a line (8.2), which uses a real IK with the bend chosen outward from the thread.

**Layering side-on:** far legs, then body/abdomen, then head, then near legs, with `faceOverLegs` (a look option) putting the face in front of or behind the near-front leg. Near-side legs in front, far-side behind and darker, feet staggered so all eight show.

**Turning is a yaw, not a mirror.** `pose.facing` runs +1 → 0 → −1; its sign picks the mirror, its magnitude blends every part between profile and front view using `profileAmount(yaw) = smoothstep(|yaw|)`. The front-view layout is symmetric under `i ↔ 7−i`, so at the exact moment the mirror flips the feet are re-paired and nothing jumps. The head and abdomen additionally draw at `facing + headTurn` (their own yaw, 5.3) — **the legs must not mirror often** (leg layering pops when the whole sprite mirrors); head and abdomen are symmetric face-on so they cross the front view unseen.

**Lean.** A lean of the body (peek, peer, nose-up/down) is `pose.bodyPitch` about `leanPivot` with `bodyShift`; the renderer turns the body, face and hat about the pivot and moves the hips with it, but **the legs are drawn outside that transform** so a planted foot never moves with a lean.

**Roll/ball.** `pose.ball` (0…1) folds the head down and under: `foldHead` translates to `neck`, rotates by `−1.2·ball`, scales by `1 − 0.15·ball`, offsets `−3·ball`.

**Contact shadow** under the spider, scaled by `pose.grounded` (1 on a surface, 0 in the air).

### 3.5 The pose (everything the renderer needs)

```
SpiderPose {
  pos, heading, facing(+1/−1 animated through 0), spin (roll), ball, grounded, silkAttach, scale,
  stretch (along body), fatten (vertical, pivoting on feet),
  legs[8] { hip, knee, foot, lift [, hipZ, kneeZ, footZ] },
  look (screen-space gaze direction), blink, happy, startled, sleep, abdomenSway,
  emote, emoteT (0..1 through its time), emoteClock (never held back; for looping Z's),
  thought,
  web? (anchor, alpha, slack), webPoints[] (the live line), thread? (a,b,tail,alpha) // stretch it is holding in sprite units
  threadFrom?, threadVia?,                    // climbing/rolling-over silk routing
  time, grabbed (0..1), outfit (SpiderLook), surroundings (RGB behind it, for camouflage),
  name, nameTag (opacity), odometer (distance walked in body units: drives propeller, etc.),
  bodyPitch, bodyShift, chew, headTilt, headCock, wink, palpNear, palpFar, headTurn, abdomenTilt,
  hiddenBy[rects], peekGrip[points],
  wet, snow, dust, chill (0..1 weather on it), specks[] (drips/splashes/puffs),
  legsInRound, layerMemory                    // only for the optional "legs in the round" system
}
```

### 3.6 The look system (SpiderLook) — what the Studio edits

```
SpiderLook { body, eyes, brows, fangs, legs, pattern, skin(kind), coat, gradient, living, custom(colours),
             customGradient, bodyTune, eyeTune, legTune (hand-shaped custom measures),
             accent, customAccent?, camoMarkings, hat, accessory, fuzz (0…2), faceOverLegs }
SpiderDesign { name, look, personality, gait, habits, packs[], customPhrases[], voice (pictures|phrases),
               intelligence (bool), manner (string) }
```
Persist as JSON; decode every field with `decodeIfPresent` and a default.

**Option inventory** (labels are user-visible; keep them):

| Part | Count | Options |
|---|---|---|
| **Body shapes** | 11 + custom | Classic (1.0,1.0,1.0), Round (1.08,1.1,1.04), Plump (1.22,1.16,0.96), Slim (0.95,0.82,0.92), Peanut (0.82,0.86,1.1), Chonk (1.3,1.26,1.12), Tall (0.9,1.18,1.0), Pear (1.12,1.3,0.8), Big Head (0.82,0.84,1.3), Bean (1.28,0.78,0.88), Petite (0.84,0.84,0.86). Triple = (abdomen rx mult, abdomen ry mult, head mult). |
| **Eyes** | 13 + custom | Classic, Huge (size ×1.22), Beady (×0.7), Sleepy, Wide (×1.08), Sparkly, Oval, Cross-eyed, Wink, Glowing, Dizzy, Heart Eyes, Button (×1.1) |
| **Brows** | 10 | None, Soft, Arched, Stern, Worried, Unibrow, Thick, Quizzical, Bushy, Flat |
| **Mouths/fangs** | 11 | fangs, tusks, emerald chelicerae of a bold jumper, a smile, a blep, a grin, buck teeth… (see `FangStyle`) |
| **Hats** | 38 | top hat, party hat, crown, beanie, flower, bow, cap, halo, wizard, propeller (spins with `odometer`), cowboy, chef, bucket, viking, tiara, pirate, mushroom, sombrero, fez, beret, bowler, santa, mortarboard, bunny ears, cat ears, antlers, hard hat, sailor, jester, horns, unicorn, ushanka, pumpkin, strawberry, sweatband, flower crown, a little bird |
| **Extras (accessories)** | 30 | glasses, monocle, shades, heart shades, goggles, eyepatch, hero mask, clown nose, moustache, beard, bow tie, necktie, scarf, bandana, bell collar, pearls, medal, flower lei, headphones, sweater, tutu, backpack, satchel, bindle, jetpack (fires in the air), balloon, cape, fairy wings, bat wings |
| **Leg styles** | 13 + custom | Classic, Slender, Chunky, Stubby, Long, Fuzzy, Banded, Socks, Spindly, Boots, Robot, Knobbly, Striped — *they change the rig* (reach/knee/width), so walk, turn and jump all adapt |
| **Coats** | 30 flat + 16 gradient + 15 living + custom | Living: Rainbow (slides along it), Hot Lava (glowing cracks between drifting crust), **Camouflage** (takes the colour behind it), Galaxy (twinkling stars), Ocean, Aurora, Disco, Fire, Frost, Toxic, Pearl, Candy Cane, Thunderstorm (lightning), Chrome, Web-Slinger (red & blue, webbed, emblem on back). Custom: pick body+leg colour, or blend 2–3 colours in any direction, shimmering optionally. Debug Legs coat (colours each leg by index — kept for tools). |
| **Markings (pattern)** | 20 | stripe, spots, chevron, heart, star, skull, moon, flower, eyespots, hourglass, tiger, leopard, checker, lightning… ; 20 accent colours or custom; `camoMarkings` makes them take the camo colour too |
| **Fuzz** | 3 levels | sleek, normal, very fuzzy (hair strokes) |

**Painting a non-flat coat.** The coat is a *colour field over the body*: the body is filled with it, and **each leg segment is painted the colour it passes through** (so a rainbow spider's legs are each a different colour). `sheen` keeps the body's own light/shadow over a paint. Lava legs are cooled rock; camouflage legs use its tones (`legTones`). Paint a leg from the **side-on spot** (sampled un-mirrored) so colours do not swap when the sprite mirrors.

**Camouflage:** the target colour is, by what it stands on — the window's colour for the current appearance on a window, the wallpaper's average colour on the screen rim — and, if the user allows screen capture, the actual pixels behind it. It **drifts** toward the target (`shown = mix(shown, target, 1 − e^(−dt·1.2))`, a 1–2 s fade — never a flash). Every shade (blotches, legs, outline — always slightly darker than the body) is a **fixed step** from that colour so nothing flips between darker and lighter as the colour drifts.

**Symmetry check:** `faceOnSymmetric` — lopsided outfits (≈41 of 181 options: most hats, eyepatch, monocle, wink, quizzical…) are detected once per look by rendering at ±ε yaw (≈0.8 ms); symmetric looks may swing the head across the front view freely, lopsided ones keep the head on the legs' side. Abdomen coat fill is drawn un-mirrored.

**Every part is drawn in the body's own frame**, so hats stay on through corners, rolls and hanging upside down, and markings turn with the abdomen.

**Geometry source of truth.** The outlines of the 38 hats, 30 extras, 20 markings, 11 mouths, 13 eye styles, the 13 leg styles' drawing and the hair/fuzz are procedural paths in `SpiderRenderer.swift` (≈ 5k lines) and `Skin.swift`. Reproduce them by reading the Swift: the thumbnails in `build/studio.png` (tools/gallery.sh) are the visual reference. Budget this as its own milestone.

### 3.7 Emotes, bubbles, name tag

- **Emotes** (`pose.emote` with `emoteT`): hearts, zzz (looping, drifting & growing), surprise, sparkle, question, note, exclaim (a burst of "!!"), charge (crackling lightning), thought (bubble). Each fades in/out over its duration.
- **Thought bubble** contents (`Thought`): heart, hungry (a juicy cricket), rain (cloud), sun, moon, music, star, bug, home (its hammock), snow, wind, storm, rainbow, text(String), dots (three bobbing dots while thinking what to say). Long text wraps into a bigger bubble. `thoughtBubbleRect(pose)` gives the clickable rect (clicking a bubble opens the chat when Talking is on).
- **Name tag** under the spider; opacity springs (`k=60, c=12`) to 1 after the pointer rests on the spider for 0.7 s (and while held); name set in the Studio.

### 3.8 Weather on the spider (art side)

`wet` (darker glossy coat, bead drops, drips off), `snow` (cap on back, slides off when it moves/climbs/leaps), `dust` (sand in the fur), `chill` (bluish tinge). `specks[]` are particles (`water, snow, sand, hail, ring`) in world space with velocity, life, floor height to splash on, gravity (default 900), ring spread. Functions: `drawWetCoat`, `drawSnowCap`, `drawDust`, `drawSpecks`. Dew drops on it (fog). Deterministic by seed so they do not shimmer.

### 3.9 The tray/app icon

The menu-bar icon is a small spider drawn by the same renderer (`Menu bar icon` MARK); dimmed while the spider is hidden; wiggles during the first entrance. The app icon is the spider on a tile (drawn by `tools/art.sh`). Windows: notification-area icon + `.ico` set.

### 3.10 Acceptance: the contact sheet

Build a `preview` tool that renders: every Studio option as a thumbnail; the spider in profile, 3/4, and front view; each leg style; each hat/accessory; a rolled ball; peek; arms up; asleep; with weather (wet/snow/dust); on a line (once Stage 8 exists). Compare against the Mac's `build/preview.png` and `studio.png`.

### Done when (Stage 3)
- A window shows the spider drawn from a hard-coded pose, correctly anti-aliased, moving with the mouse (hand-dragged); toggling the Studio options (temporary debug UI) changes it.
- Profile → front → profile turn sweep (yaw +1 → −1) shows no leg flip.
- Clip rectangles cut it correctly; peek grip dots show through.
- Sprite redraw count while only translating is zero.

---

# PART C — THE BODY AND THE POINTER

## Stage 4 — The body: modes, kinematics, gait, legs, turning

### Goal
The spider stands on a surface, walks along it in a believable tetrapod gait, rounds corners, turns round through a front view, and is carried by moving windows. Driven by hand-issued commands ("walk", "turn", "stand") before any brain exists. This is the stage the owner judges hardest: **the flat walk must look like the reference**.

### 4.1 Modes

```
Mode { attached,    // standing/walking on a surface
       airborne,    // jumping, falling, thrown (AirKind: jump | fall | thrown)
       dangling,    // on a silk line (WebStyle: hang | swing)
       held,        // in the user's hand
       nesting,     // in its hammock (NestPhase: building | entering | sleeping | leaving)
       clinging }   // hanging off the pointer after catching it
LegMode { planted, free }
LegController { gait, turn, posed, hang, … }   // which logic currently places the feet
```
`Spider.update(dt)` runs a fixed order every frame (keep it): track cursor → interest → body language → emote → blink → memory → beat; clear landing/mantle state; pending demo; then the mode update (`updateAttached | updateAirborne | updateDangling | updateHeld | updateNesting | updateClinging`); **heading spring**; head/abdomen tilt springs; `updateWeb`; `updatePrey`; `updateToys`; `senseTank`; hammock upkeep; `updateLook`; `updateWeather`; **rope update before legs when on a line** (so feet hold the silk where it lies this frame); `updateLegs`; name tag; odometer; roll ball; stretch/fatten/happy/startled springs; `updateYaw`; `updateHeadTurn`; grounded spring; wag phase; volume preservation; rope update (when not first); `updateKnees`; `syncTraces`.

### 4.2 Spring master table (stiffness, damping)

| Quantity | k | c | Meaning |
|---|---|---|---|
| lift | 140 | 21 | height of body above the ledge (units) |
| pitch | 120 | 20 | nose up (+) / down (−) |
| crouch | 200 | 25 | body let down onto folded legs (`crouchDrop` = 7.5 units at crouch 1) |
| wag | 90 | 12 | abdomen wiggle amplitude (`wagPhase` runs at `6 + wag·4` rad/s) |
| stretch / fatten | 320 | 20 | squash & stretch; fatten ≈ `1/max(0.6, stretch)` (volume preserved) except balled/curled |
| lookSpring (Spring2) | 150 | 16 | gaze direction |
| happy | 120 | 14 | |
| startled | 190 | 17 | |
| sleepiness | 40 | 12 | |
| lid | 60 | 13 | heavy eyelids |
| grabbed | 200 | 18 | |
| grounded | 120 | 18 | contact-shadow/stance blend |
| nameTag | 60 | 12 | |
| windOn | 40 | 9 | weather lean |
| heading (manual) | 190 | 21 | `headingVel += (err·190·soft − headingVel·21·√soft)·dt`; `soft = 0.4/0.5` on a line (hang/swing), `0.55` for 0.4 s after landing, else 1 |

Targets are set by the **posture** table (4.3); never assign these values directly except to `nudge` velocity for impulses (`happy.velocity = 7`, `startled.velocity = 12`, `stretch.velocity = −5`).

### 4.3 Posture table (the character of every activity)

Each activity returns a `Posture {speed, lift, pitch, crouch, wag, lid, legsFree}`, with `u = activityTime/activityDur`. `legsFree` means the legs are placed by pose (not by the walk gait). Values (units / radians / multipliers):

| Activity | speed | lift | pitch | crouch | wag | lid | legsFree | notes |
|---|---|---|---|---|---|---|---|---|
| idle | 0 | 0 | | | | | | |
| walk | 1 ± 0.12·wobble | gait style: bouncy +2, tiptoe +3.5 (speed×0.8), lumber −1.5 (speed×0.7, wag 0.5) | | | | | | **Walks in bursts**: after `walkPauseAt` (next = +0.9…2.2 s) it stops for `walkPauseFor` 0.25…0.7 s: speed 0, pitch 0.05, lift 0.5 (1.4 if checking in on you); no new pause in last 1.2 s |
| sneak | 0.42 | | −0.08 | 0.4 | | | | |
| scurry | 1.9 | | −0.12 | | | | | |
| look | | 1.5 | 0.06 | | | | | |
| rest | | −4 | | 0.28 | | 0.35 | | |
| groom | | | −0.15 | | | | ✓ | |
| sleep | | −5 | | 0.4 | | 1 | ✓ | |
| wave | | 2 | 0.16 | | | | ✓ | |
| startle | | 5(1−u) | 0.3(1−u) | | | | | |
| crouch | | | −0.1 | 0.85 | 1 after u>0.3 | | | the pounce wiggle |
| turn | | hop: 3·sin(uπ); shuffle: crouch 0.18·sin(uπ) | | | | | | flip happens in `updateYaw` at the front view |
| peek | | −1 | −0.38 | | | | | |
| stretch | | 6·sin(uπ) | 0.22·sin(uπ) | | | | ✓ | |
| shake | | 1 | | | decays | | | heading jitter `sin(t·62)·6·decay` |
| wiggle | | 1.5 | | | 1.4 | | | |
| bounce | | 3.5·\|sin(3πu)\|·env | | 0.3(1−b)·env | | | | env = min(1, 8u, 8(1−u)); feet never leave the ledge |
| curious | | 2 | −0.2 | | | | ✓ | |
| armsUp | | 2 | 0.22·sin(min(2u,1)·π/2) | | | | ✓ | |
| roll | see 6.5 | | | | | | | gather → ball → roll → land |
| dance | | 1.5+\|sin(6πu)\|·3 | sin(6πu)·0.08 | | 1.6 | | | |
| glance | | 1 | | | | | | |
| peer | | −3 | −0.42 until u=0.8, then back | | | | | |
| pushup | | −4 + (1−\|sin(4πu)\|)·5 | | | | | | |
| legStretch | | 1 | −0.06 | | | | ✓ | |
| shoot | | 1.5 | 0.18 | 0.15 | | | ✓ | one front leg points along the line |
| eat | | −2.5 | −0.16 | 0.15 | | | ✓ | |
| stare | | −1 | | 0.12 | | | | |
| hop | stage 0 sink (crouch 0.4 / 0.65 for joy leap), 1 push (lift to `hopTakeoff`=2), 2 air (lift = 2+4·7·v(1−v); `hopHeight`=7; legsFree), 3 land (give) | | | | | | | |
| drum | | −1 − together·1.5 | −0.06 | 0.18 | 1.2 on beat else 0.4 | | ✓ | 1.45 s cycle |
| greet | | 3 | | | | | ✓ | |
| peekaboo | pace/walkSpeed | out: 3 / in: −2 | out 0.2 / in −0.1 | 0.3 when hidden | | | out only | |
| fasten | | −1.5 − dab·1.5 | 0.16+dab·0.1 | 0.3+dab·0.2 | 0.8+dab·0.6 | | | dab = 0.5+0.5·sin(3πu) |
| groove | | 0.5 | | | | | ✓ | |
| watch | | on floor: −5; else −1 | 0.12 / 0.08 | 0.34 floor | | 0.06 | | |
| brace | | −3.5 | | 0.55 | | 0.45 | | |
| bask | | −3 | 0.07 | 0.2 | | 0.55 | | |
| feel | | 1 | −0.06 + clamp(y/40)·0.35 | | | | ✓ | |
| drink | | −3.5·down·deep | −0.46·down·… | 0.2·down | | | ✓ | |
| doubleTake | | 3·jolt (+1 after 0.45 s) | 0.08·jolt | | | | | |
| sigh | | 2.6 up − 4.2 down | 0.1 up − 0.1 down | 0.3 down | | 0.6 down | | |

Modifiers applied after the table: `worn` carriage (pitch×profile, lift, pace) for on-foot activities; a stationary posture (speed 0) adds `liftWobble·0.8` so it is **never quite still** (slow shift of weight, breathing, darting eyes, blinks singly or twice); `gait.liftOffset` except sleep/rest/roll/crouch; weather posture.

Walk speed: `targetSpeed = config.walkSpeed(62 px/s at scale 1) × posture.speed × bout × (0.75 if carrying a catch) × (0.7 if towing)` where `bout` is a per-walk-bout multiplier. Speed approaches `targetSpeed` with an acceleration spring (gets going over a few steps, stops short, **leaning into starts and rocking forward on stops** via `inertia`).

### 4.4 Moving on a surface

- State: `anchor (loopID, segIdx, t, dir)`, `walkDir` (±1 along the seg), `facing` (±1), `speed`. Position = `map.resolve(anchor).pos + rideShift`.
- `advanceAlong(dist)`: moves `t`; at a segment end goes to the next seg (wrapping on closed loops); **at an open run's end** it must turn back or jump. In the habitat, entering a junction vertex *while walking into it* may cross to the other loop (`crossJunction`: forced at a run's end, 30% optional otherwise, never when purposeful or rolling; `walkDir` is kept so the belly stays to the surface).
- It never walks into a **blocked** stretch: `seg.limit(from:dir:)`.
- Heading target follows the surface tangent (with rounding at corners). Standing on a downward-facing seg flips it upside down (heading π).
- **Safety nets** (keep them; they exist because of real bugs): a window that jumps >400 units in one poll (another Space/display) → `detachAndFall()`; walking at speed >4 for 1.2 s while not moving 0.5 units → detach and fall; an anchor that no longer resolves → fall (a vanished page ledge shoots a line up to catch itself); a surface off-screen for >10 s → `climbBackOnScreen()`.
- **Carried by a moving window:** the anchor persists on the loop; positions re-resolve each frame so it rides along; `surfaceMotion` records the surface's own motion so planted feet ride with the ground (and a stopping spider does not slide its feet).
- **Landing** sets `landedAt`; `landDrop`/`landHold`(0.5 s)/`landAbsorb`(0.35) let the body fall onto its legs, which take the blow and give under the rest; heading swings square over ≈0.4 s (`soft 0.55`).

### 4.5 The classic gait (the 1.0.0 leg system — build this one)

**Tetrapod, distance-driven.** Four legs swing while four stay planted; planted feet hold still in the **world** while the body moves over them.

```
strideLength = 28 body units per gait cycle        // scaled by gait.stride dial & style
swingDuty    = 0.34                                // fraction of the cycle a leg is in the air
phase(i): k = i%4, near = i<4; group = ((k%2==0) == near) ? 0 : 1
          phase = (group==0 ? 0 : 0.5) + (3−k)·0.03       // 3 hundredths between neighbours so they never move in lockstep
cycle advance per frame = speed·dt / (strideLength·scale)
```
(The cadence at Small is ≈ 2.3 steps/s; the body bobs **twice per cycle** and planted legs flex against the bob.)

Per leg per frame while walking:
1. **Stance** (phase ≥ duty): the foot is fixed in world space: `foot_local = (foot_local rotated by −dTheta) − overFeet`, where `overFeet` = body motion in the body frame minus the surface's own motion. Lift decays to 0 (`approach rate 16`). If the foot is more than ~2 units off the ground it eases to `groundFoot(foot)`.
2. **Swing** (phase < duty): at start record `swingFrom` and `swingPh0`; `u = (ph − ph0)/(duty − ph0)`; position = `stepPath(i, from, to, u)` (an arc: ease from → target) with `lift = sin(uπ)`; the foot rises `lift × 4` units; the target is the leg's rest spot `groundFoot(rig(i,profile).foot, spread:true)` shifted ahead by the stride. A step that would begin with the clock already part-way through its window **waits for the next one** (`skipSwing`).
3. **Corner footholds:** a leg that the spread placement would over-stretch swings about its hip, keeping its flat-ledge span, to where its foot meets the ground (`cornerFoothold`/`swingToGround`/`surfaceSide`) — faded in by cornerness × how over-stretched; never for folding into inside corners (looked worse). Classic knee bones are capped at the flat-walk envelope (`cornerKnee`: `flatThigh`/`flatShin`, measured at scale 0.62 over all styles but scurry) and the knee *opens* instead.
4. **Reach limit:** `limitReach` keeps no foot past `legLength × reachLimit(1.25)` (plus `(strideNow − longStride(45))·0.5` at a run) from its drawn hip; a reach target is `legLength × reachShare(0.94)`.
5. **Jolt limiter:** the last word on the feet — a foot cannot pick up speed faster than `footJolt = 26 000 px/s² × scale` (only speeding up is capped; a foot may stop at once). A foot held back past its own hip goes *round* the hip at arm's length (swing about hip), not through it.
6. **Settling:** a foot left mid-stride when a walk stops takes one small step to its place, **one leg at a time** (never a slide); a foot left in the air by a previous pose (wave/greet/line grip) *steps* down, folding at the knee on the way (not sweeping down as a bar). `settleFoot`.
7. **Hand-offs between controllers** (`handoffTime` 0.26 s): when the leg controller changes (walk → pose → line), feet ease from where they were — on a surface the start point stays on the ground while the body moves; on a line it goes with the body and swings round the hip.
8. **Turning on the spot:** `turnGait += dt·2/max(duration,0.3)`; feet step round in the usual tetrapod waves timed to the rotation; targets are the profile-blended rest spots; a **spin** = two turns back to back.

**Gait styles / dials.** `GaitStyle {normal, bouncy, tiptoe, lumber}` + preference (mixed, steady, bouncy, tiptoe, lumber, scurry); dials `pace, stride, bounce, stance` (0…1) and `bounciness` (0 = lands where it hits; up = bounces off from gentler hits with more spring: `restitution = lerp(0.28, 0.72, b)`). Each walk bout picks its own speed/stride/bob/gait style plus a slow drift in pace within the bout.

### 4.6 Knees

Classic: the **art-driven knee model** of 3.4 (rest shape swung about the hip, folded when short). Knee jolts are limited. Further rules from the owner's corrections:
- `kneeOver`: knees must not bend through the surface; ignored only where the ledge line runs over a drop; uses a rounded-rect SDF near window corners.
- On a line, a real two-bone IK with outward bend (8.2).
- Legs never swap places on screen for the classic system (that rule applied to the abandoned rework; classic is the reference as shipped).

### 4.7 Turning and yaw

`yaw` runs +1 (profile facing +) → 0 (front view) → −1; `facing` flips as it crosses 0; the sprite mirror follows `mirrorSign`. A turn is an activity (`turn`, styles `hop` or `shuffle`). Rules:
- The turn *sweeps* through the front view and out the other side; legs re-pair at the mirror (`i ↔ 7−i` in classic).
- A turn begun **face-on** (after a greeting) sets off from the front view rather than snapping to profile first.
- **Head and abdomen have their own yaw:** `headTurn` (drawn at `facing + headTurn`), target `0.9·cos(bearing)` to the pointer, spring ω≈15, max ±0.6 from the legs. The legs follow lazily: `stanceShift` only when ≥0.3 off, or after 1.2 s settled; side flips use the old rule (0.3 past, 0.5 s). While the legs turn, `headTurn` is compensated so the upper body stays on the pointer. (Details and the smooth-follow rules are in 5.5.)
- Pitch toward the pointer: `nose = atan(0.9·sin bearing)`; head tilt `0.85·nose`; abdomen tilt `0.7·nose` (tail down looking up); face-on, `headRise`/`faceRise` slide the face up the head; body lean share × profile only.
- Turning on a hang is **never** done to show the other side (it would put its head beside its abdomen); a body offset eases over while the spinnerets swap sides in sprite space.
- Never turn the body back while *walking* (no walking backwards) — see 6.2.

### 4.8 The optional leg systems (build last, behind toggles)

The owner asked for these as *additional* options, with classic untouched and byte-identical when they are off:

| Option | What it is | Key facts |
|---|---|---|
| **Natural walk** (`Gait.motion = natural`) | Every leg keeps its true length (IK knees); steps ripple back to front; pattern changes with pace. | Looks squat/straighter. Range per leg ≤ 0.88 of leg, ≥ max(fold, 0.5·leg) out from the hip. `strideNow` caps stride so stance fits reach (cadence rises). |
| **Refined walk** (`motion = refined`) | Classic look + true-length legs, with a **capped smooth give** (bones up to +12% at 1.35× reach, blended from lift-off to touchdown). The owner's own spider uses this. | Footholds predicted at mid-stance, measured *along the surface* (fixes inside-corner floor/wall ambiguity); 1-D cost search along the edge; steps interpolate joint angles; rate-limited targets (60 units/s) and frozen after u 0.6 at corners; `refGroundNear` (true nearest point on the arc — `groundFoot` is not idempotent on rounded corners and planted feet crept 8 px per stance). |
| **Legs in the round** (`Gait.newLegs`) | Full 3D legs with fixed identity (front/front-middle/back-middle/back per side), depth-layered. | 10 rounds of tuning; owner judges the *drawn* crossings. **Do not build this unless asked.** It exists only in the Mac app's latest build behind a checkbox; the first attempt was removed after the owner called it "horrible". |

**Verification discipline for any leg change:** flat window-top walking must come out **identical** to classic at all five sizes; corners improve; check all leg styles.

### 4.9 Done when (Stage 4)
- A debug harness commands: `walk`, `turn`, `stand`, `sneak`, `scurry` on a window top, around its rounded corner, down its side, under its bottom, along the screen rim and across the taskbar.
- Feet are visibly planted (zero slide) and step in alternating groups; the body bobs twice per cycle.
- Round a Win11-radius corner (8 px) and a 26-unit corner: no leg longer than the flat envelope, no knees through the surface.
- A window dragged while the spider stands on it carries it with no foot slide.
- Turn on the spot sweeps through the front view without leg flicker; start/stop shows lean-in and rock-forward.
- All checks repeat at scales 0.62, 0.78, 0.95, 1.2, 1.55.

---

## Stage 5 — The pointer: touch, drag, throw, scroll, watch

### Goal
The user can poke, pick up, carry, throw, stroke, scroll and right-click the spider, and it watches the pointer.

### 5.1 Hit-testing and pass-through
See 3.1: `grabRadius = 30·scale`; clicks pass through everywhere else. The spider also ignores the pointer when the Click-to-Pick-Up option is off.

### 5.2 Click, double-click, right-click
- **Single click → `poke()`:** `wake(); remember(.greeted)`; pick one reaction by weighted draw (weights shown with the personality factor):
  `wave` 1.5 s (3·love; sparkle) · `armsUp` 1.2 s (2·love; hearts) · `greet` 1.8–2.6 s (3·love; hearts) · `drum` 2.9–4.4 s (1.5·playfulness-scaled; note) · `startle` 0.55 s (2·jumpy; surprise) · `curious` 1.4 s (1.5·curiosity-scaled; question) · `glance` 1.2 s (1.5) · `wiggle` 0.9 s (1.5·playful-scaled) · **grumpy turn-your-back** (look 0.6 s, then turn the other way; 50% a head shake first; weight 1.0·`lerp(1.8, 0.1, affection)`) · **curt nod** (look 1.2 s with 1–2 nods; weight 1.2·`lerp(1.4, 0.3, affection)`) · **slow blink** (stare 1.8–2.4 s; weight 1.0·`lerp(0.2, 1.4, affection)`).
  where `love = lerp(0.3, 1.6, affection)`, `jumpy = lerp(1.6, 0.25, bravery)`. Then `stretch.velocity = −5`.
- **Double-click:** happy bounce-and-wiggle, or a dance with arms up (stays "celebrate" even when Talking is on).
- **Right-click:** the context menu — **except** when Talking is on and the spider/bubble was clicked, which opens the chat directly (18.1); right-click elsewhere in the tank still shows the menu.
- Hover: rest the pointer on it >0.7 s (not held, speed <30) → name tag fades in.

### 5.3 Pick up, carry, throw
```
beginGrab(p): tumbleVel = 0; clear line orders, climb arrivals, build (abandonBuild), cursor hunt, departLeap;
              isHeld = true; mode = held; activity = idle; grabOffset = pos − p;
              grabbed.velocity = 6; startled.velocity = 9; emote surprise 0.7 s; legMode free; wake()
moveGrab(p): cursor = p                       // the held body follows cursor + grabOffset via springs
endGrab(throwVelocity v):
    speed = v clamped to length ≤ 2700;  remember(speed < hardThrow ? carried : thrown)
    if a line is active (webActive):  mode = dangling; slingshot on the thread (webAngleVel from v)
    else: mode = airborne, air = thrown, vel = speed, noAttachFor = 0.06;
          if speed < hardThrow: planFall(lineUp: true)   // a drop or light toss: shoots a line up and catches itself
          // flung hard: it flies
    stretch.velocity = −4; legMode = free
```
Held posture: legs curled (`curl = hip + reach·0.45` plus a kick of `sin(t·9+1.1i)`/`cos(t·7.5+0.9i)`·3.2), wriggling. The drag velocity is the pointer's recent velocity (a few frames, smoothed). Throwing it hard enough lets it catch itself on a web. `hardThrow` is a speed above which it just flies.

### 5.4 Scroll
`scroll(dy, precise, startsGesture)` — accumulate a gesture; threshold `4` (trackpad points) or `0.5` (wheel lines); a new gesture begins when the device says so, or after a 0.35 s pause; `scrollGave` stops a second order from the same gesture unless the swipe reverses. **One swipe = one order.** `obey(up:)`:
- **attached, scroll down:** `lineOrder = .drop`; if webs enabled and `canRappel(userAsked:)` → `dropOnWeb()` (rappel about halfway to whatever is below and hang; it may go about its business after a long hang). Scroll up on a ledge: nothing.
- **airborne stepping off on its dragline:** record the order; once the line takes weight it goes as told.
- **dangling:** if mid-swing it stops working the swing; `lineOrder = up/down`; `webPlan = [climbHome | toFloor]`; target length `lineTop − 4·scale` (up) or `floorLen` (down); clears linger/joy timers; `decisionIn = 0`.
- In a box with `hangOnly`: only up/down the line within the box; stays a while (`decisionIn ≥ 12`).
The pointer that sent it does not draw it back; it picks up a fresh plan of its own after. See also 8.5.

### 5.5 Watching the pointer (the character-defining behavior)
Settings: **Watch the Cursor** (`followCursor`: eyes, head, look gestures) and **Come to the Cursor** (`approachCursor`: walks over, pays out line toward a pointer below, playful jump spots) — separate toggles; tools that disable one must disable both. Also **Pounce on the Cursor** (`pounceOnCursor`).

**Interest.** `interest` (0…1) builds when the pointer is near/moving and the spider is at leisure (`interestRange = 170` units). Parked-pointer fix: the app only calls `setCursor` on movement, so interest needs <8 s of activity; a pointer untouched for 20 s (`pointerFresh`) is "old news" and not worth a trip; after ten or twenty seconds it stops noticing a parked pointer.

**Noticing.** While sitting about or ambling it turns to face the pointer, eyes on it, head tipped toward it, up on its toes and leaning after it; straight overhead it squares up and looks up. **Busy** (hunt, errand, film, nap, laser, toy) it does not stop for you.

**Continuous follow (the final, owner-approved version).** Standing and watching (not moving, not gesturing):
- `bodyBearing` follows the pointer bearing at `followRate = 20/s`; `interestYawTarget = 0.88·bodyBearing` continuously across the front view, with side hysteresis (`followFlip` 0.06, `followLeast` 0.04) so a pointer hovering overhead never flips it.
- Body spring stiffer while following (up to 360/36); head spring up to 640/48; the head **looks ahead** by `headLead = 0.08 s` of its target's velocity.
- Legs: `keepPlanted` starts with "go round with the body" when `rotRate > rotFollow 0.5` — each foot rides its rest spot, placed *before* the on-the-ground guards; a foot is planted exactly between steps and catches up in a lifted step (watching rotations **step, not slide**).
- `watchingPlanted` (interest, standing, look/idle/rest/stare/glance/peer) → feet hold in the world, stepping one at a time if >6 units off (2.5 once the stance has been still 0.35 s).
- Face-on symmetry: glints (`glintSide`), palp widths, blush sizes mirror correctly; lopsided outfits keep the head on the legs' side of the front view (`faceOnSymmetric`).
- `headPinnedFor`: if the head is at its limit but wants further, the legs switch sides after 0.08 s on the raw bearing; `stare` follows `interestSide`; curious/greet/armsUp/wave give way to `look` when the pointer goes well round; an aimless walk is dropped 4× sooner with the pointer behind.
- Measured outcomes to match: mean head error ≈ 0.05 rad; stalls ≈ 0.03 s per scenario; hover → 0 flips.

**Pointer events that provoke behavior** (`trackCursorMotion`):
- **Rest the pointer near:** greet.
- **Whip the pointer past it** (fast, within a hand's width): **nervous hop** — small startled hop on the spot, legs tucked an instant, "!!" burst. It does **not** run. Only the pointer whipping right across its body properly startles it.
- **Swipe at it fast:** startled, scurries away (bravery decides; a grumpy/brave one stands its ground).
- **Stroke** (move the pointer back and forth over it): squints, blushes, wiggles, puffs hearts.
- **Fidget the pointer** close like something alive: it decides you are prey — freeze, creep along the ledge, poised wiggle, springs at it and catches it (`cursorHunt: stalking → pouncing → clinging`), then **hangs off the pointer by its front legs** (mode `clinging`) for a few seconds, swinging as you drag, before dropping away on a line; shaking the pointer fast flings it off sooner (`clingShake`). Legs when clinging: front two pairs hooked round the hotspot past the mouth, the rest tucked and kicking harder the more it is shaken. While clinging, every click passes through it (`hitTest` is false in `.clinging`).
- Cursor **inside a Box** or outside the visible tank is "not free" and ignored (`cursorFree`).
- The `setCursor` is only called on mouse movement in the app (a parked pointer builds no new interest).

### 5.6 The nervous / reaction vocabulary tie-in
Reactions to the pointer feed `remember(...)` events for the memory system (Stage 13): greeted, stroked, scared, carried, thrown, played, etc.

### Done when (Stage 5)
- Click, double-click, drag, flick-throw, scroll, right-click all work on a spider walking on a real window; clicks elsewhere reach the apps underneath.
- Throwing it hard at the screen edge bounces/tumbles per the `bounciness` dial; a soft toss ends with a rescue line catch.
- Sweeping the pointer across it makes the head and body track continuously with no mid-swipe stall or leg flip; a pointer hovering overhead does not flip it.
- Pointer whip → hop; fidget → stalk → pounce → cling → drop.

---

# PART D — THE BRAIN, THE AIR, THE SILK

## Stage 6 — The brain: decisions, moods, the activity repertoire

### Goal
Left alone, the spider lives: it wanders in bursts, stops to look, grooms, rests, naps, shows off, and reacts to you — with a personality you can tune. This is the stage that makes it feel alive; budget accordingly.

### 6.1 Inputs that shape every choice

- **Personality** (six 0…1 sliders): `energy` (how often it does anything; `liveliness = lerp(0.45, 2.4, energy)`), `curiosity` (interest in the pointer), `bravery` (hard to startle), `playfulness` (dances, rolls, spins, hops), `affection` (waves, glances, hearts), `laziness` (rests, naps; default 0.3). Presets: Friendly (.55,.7,.6,.55,.85,.25) · Shy (.4,.35,.15,.3,.4,.35) · Hyper (.95,.7,.7,.9,.6,.05) · Lazy (.2,.3,.6,.2,.5,.9) · Curious (.6,.95,.55,.45,.5,.2) · Show-off (.7,.5,.85,.95,.7,.1) · Chill (.35,.45,.75,.35,.55,.5) · Grumpy (.45,.3,.9,.1,.15,.45). Order: energy, curiosity, bravery, playfulness, affection, laziness. Random: energy 0.15–0.95, curiosity/bravery/playfulness/affection 0.1–1, laziness 0–0.85.
- **Learned shifts** (Stage 13) bend personality ≤ 20% toward experience; `learned.lean(habit)` multiplies habit weights.
- **Habit dials** (`Habits`, 0…1 each, default 0.5): see 6.4. `Habits.weight(v)`: `v ≥ 0.995 → 100 000` (every chance it gets), `v ≤ 0.5 → max(0, 2v)` (0 = never, 0.5 = as usual), else `400^((v−0.5)·2)`. Dialled to never ⇒ not in the hat at all.
- **Context:** drowsiness (Low Power: `lerp(1, 0.5, drowsy)` on play, decision clock slows), confinement to a box (`chill 0.4`, decisions ×2.2 slower), hunger (tank only), idleness, interest in the pointer, mood.
- **Derived multipliers** used in the draw: `play = lerp(0.25, 2.2, playfulness)·chill·lerp(1, 0.5, drowsy)`; `love = lerp(0.2, 2.2, affection)`; `lazy = lerp(0.3, 2.4, laziness)/chill·lerp(1, 2, drowsy)`; `busy = lerp(0.5, 1.6, energy)·chill·lerp(1, 0.55, drowsy)`.

### 6.2 The decision loop

`decisionIn` counts down by `dt·liveliness·lerp(1, 0.55, drowsy)` while `activity == idle`; at ≤ 0 → `think()`. `think()` first re-arms `decisionIn = randRange(1.0, 3.4)/max(liveliness, 0.25)` and clears routing state, then evaluates **priorities in this order — the first that applies wins and returns**:

1. Riding a carried thing → `brace` (60 s).
2. Just woke after you were away → `greetYou()`.
3. A visitor going home → `pursueDeparture`.
4. **Cinema** (full-screen video): watch (14.1).
5. `homing` (heading for/hammock errand) → `pursueHome`.
6. **Laser dot** → `chaseLaser` (nothing else matters).
7. Game of tag with a visitor → `chaseFriend`/`fleeFriend`.
8. Stalking the pointer → `stalkCursor`.
9. Strayed outside its Box → `returnToBox`.
10. Holding a meal → carry it somewhere quieter (≤10 s), then `eat` for `kind.mealTime × 0.9–1.15`.
11. A hunt-worthy `quarry()` → hunt (decision interval shrinks to 0.25–0.7 s ÷ liveliness ÷ (1 + prowess·2)); ends toy play and errands.
12. A toy it is playing with / feels like playing with → `playWithToy`.
13. A web job under way (`webJob`) → `pursueWeb`.
14. Music just started → `startGroove()`.
15. Tank errand in progress → `pursueErrand`.
16. Weather on it (wet/snow/dust/cover goal) → `weatherMind`.
17. A fright in the tank → hide.
18. Something new in the tank → inquiry (curiosity).
19. **Sleep:** if `idleFor > lerp(120, 20, laziness)·lerp(1, 0.35, drowsy)·(1 + 2·hunger)` (or sleep dial maxed) and `chance(min(1, lerp(0.1, 0.6, laziness)·lerp(1, 1.8, drowsy)·hw(sleep)))` → in the tank go to where it sleeps best; else to a finished hammock (70%); else head to a window top (60%, thought "moon", `bedBoundUntil` 45 s); else `rest` 8–20 s×(0.7+laziness).
20. On the way to bed → continue, or rest then queue `sleep` 40–120 s×(0.7+laziness).
21. A pointer trip in progress.
22. **Eye on pointer** (`followCursor||approachCursor`, within 340, cursor free, `chance(min(1, lerp(0.1, 0.65, curiosity)·hw(approach)))`): if `approachCursor`, farther than 70, interest < 0.5, pointer still > 0.4 s, not snubbed, fresh (<20 s): walk toward it (`PointerTrip`) or, when it is below the window it stands on, drop a line to it (`dropToPointer`); otherwise a `look` at it.
23. **Peek-a-boo** when someone's about and an edge is near (Stage 9).
24. In the tank: `startTankGoal` (errands, 17h).
25. **The weighted draw** (6.3).

**Moods** (intentional wandering — the owner: "tons of personality still but he should not look like he is changing his mind every second"):
- `Mood {roam, potter}` with `moodUntil`/`nextMood()`. Undersides always count as roam. Roam: `goW 2.4, sitW 0.5, showW 0.85, awayW 1.3`. Potter: `goW 0.15, sitW 1.3, showW 1.7, awayW 0.3`; pottering, things last `linger = randRange(1.4, 2.2)×` longer.
- **Heading commitment:** `faced()`/`mayTurnBack`/`keepHeadingFor` (6–14 s) are set on every facing change (turn crossing, yaw crossing, landing). While committed it will not reverse; `wanderWay()` + `roomAhead()` choose a direction; `bestJumpSpot(behind:)` penalises spots behind it (`behind = mayTurnBack ? 0.7 : 0.1`). Reversals must be purposeful (room, pointer at rest, a reason) — **never** let the body face back while walking. Reference numbers: direction flips 5.1 → 3.3/min, turning back before going anywhere 0.58 → 0.17/min, quick re-turns 0.46 → 0.13/min.
- `whimBeat()` after an activity ends naturally while `atLeisure` (not after a bare idle, or it re-arms forever): `decisionIn = max(decisionIn, whimBeat·liveliness)`.
- `manner` keeps pace/style/sneaking for a whole outing.
- The pointer is approached only once at rest (`cursorStillFor`), not round behind unless free to turn or it sat 1.5 s.

### 6.3 The weighted draw (the default repertoire)

`options.append((weight, action))`; one weighted pick (`draw`). **If `interest > 0.5`** (the pointer has its attention) only the "attention" set is offered and `decisionIn = randRange(1.6, 3.2)`:

*Attention set:* look 10·hw(look) [1.4–3.0 s] · stare 6·lerp(0.6,1.4,curiosity)·hw(stare) [2.5–5] · curious 5·lerp(0.5,1.5,curiosity)·hw(curious) [1.2–2.2] · greet 4·love·hw(greet) [1.6–2.4, happy +4] · armsUp 3·play·hw(armsUp) [0.9–1.4] · wave 2·love·hw(wave) [1.5] · fidget 3·hw(fidget) [0.7–1.2] · peer 2·hw(peer) [1.0–1.6]. (Gesture weights also carry `gestureWeight(...)` for variety.)

*Out-and-about set (no pointer attention):*

| Action | Weight | Duration / notes |
|---|---|---|
| **Wander** | `30·busy·hw(wander)·goW` | turnTo(`wanderWay()`) then walk/sneak/scurry. `sneaks` = manner or chance(`lerp(0.3, 0.05, bravery)`); `hurried` = `lerp(0.04, 0.22, energy)·lerp(1, 0.2, drowsy)`; walk 1.4–5.0 s, scurry 0.5–1.2 s; pottering caps at 0.7–1.6 s. **After arriving** (30% look 0.7–1.6 s · 15% glance 0.8–1.4 · 10% peer 1.2–1.8 · 7% groom 1.4–2.4 · else nothing) — "a walk is for something". |
| look | `10·hw(look)·sitW` | 0.7–2.2 s ×linger |
| rest | `6·lazy·hw(rest)·sitW` | 3–8 s ×linger (in the tank, 65% to its resting spot) |
| groom | `6·hw(groom)·sitW` | 1.4–2.8 s ×linger |
| fidget | `6·(0.5+busy·0.5)·hw(fidget)·sitW` | 0.7–1.2 s |
| scratch | `4·hw(scratch)·sitW` | 1.0–1.6 s ×linger |
| wave | `2·love·hw(wave)·gestureWeight·showW` | 1.5 s |
| wiggle | `2·play·hw(wiggle)·…·showW` | 0.8 s |
| glance | `3·love·hw(glance)·sitW` | 0.8–1.6 s |
| greet (pointer within 520, active <30 s) | `3·love·hw(greet)·…·showW` | 1.8–2.6 s, 50% hearts |
| stare (pointer within 560, active <40 s) | `3·love·lerp(0.6,1.4,curiosity)·hw(stare)·sitW` | 3–7 s |
| muse (thought) | `4·lerp(0.5,1.5,curiosity)·(rain?1.8:1)·hw(muse)·sitW` | → a thought (6.7) |
| double take | `1.4·lerp(0.5,1.5,curiosity)·lerp(0.6,1.4,playfulness)·hw(glance)` | roaming, full carriage scope, gap `doubleTakeGap` |
| sigh | `1.2·lerp(0.4,1.8,laziness)·lerp(1,1.6,drowsy)·hw(rest)·sitW` | 1.8–2.4 s |
| drum | `2.5·play·lerp(0.6,1.4,energy)·hw(drum)·showW` | 2.9–5.8 s, note emote |
| peer | `3·lerp(0.4,1.8,curiosity)·hw(peer)·sitW` | 1.2–2.0 s |
| armsUp | `2.5·lerp(0.5,1.5,(affection+bravery)/2)·hw(armsUp)·…·showW` | 0.9–1.5 s, 50% sparkle |
| roll (only on top of something, `rollWay()`) | `2·play·hw(roll)·showW` | 1.5–1.9 s then shake 0.45 |
| dance | `1.5·play·hw(dance)·…·showW` | 1.2–2.0 s, note |
| dance-to-music again | `3·play·hw(danceMusic)·showW` (if `mayGrooveAgain`) | |
| explore (tank rearranged) | `24·busy·lerp(0.7,1.4,curiosity)·(roaming?1.3:0.6)` | |
| pushup | `1.5·busy·hw(pushup)·showW` | 1.2–1.8 s |
| legStretch | `1.5·(0.5+lazy·0.5)·hw(stretch)·sitW` | 1.6 s |
| spin | `1·play·hw(spin)·showW` | |
| look back (if `mayTurnBack`) | `2·hw(look)·sitW` | turnTo(−walkDir) then look |
| underside: let go | `14·goW` | `dropOffUnderside()` else walk on under it |
| **Leap** | `8·hw(leap)·chill·awayW` | `bestJumpSpot` → `startJump` (7.1); no spot ⇒ walk on |
| **Rappel** | `8·hw(rappel)·chill·awayW` (if webs && `canRappel()` = hanging under something) | `dropOnWeb` (8.3) |
| **Swing** | `7·hw(swing)·lerp(0.6,1.4,playfulness)·awayW` (not confined) | `startSwing` (8.6) |
| Little web (trace job) | `3.5·lerp(0.6,1.4,laziness)·lerp(0.7,1.3,curiosity)` | needs Leave Traces on |
| Build hammock | `1.6·hw(hammock)·lerp(0.6,1.6,laziness)` if hammocks enabled, none exists, `t > 45`, not confined | |
| Nap in hammock | `1.5·lerp(0.2,2.5,laziness)·hw(nap)` if a finished hammock | |
| Mend hammock | `10·hw(hammock)` if damaged (>0.08) | |
| Finish hammock | `12·hw(hammock)` if half-spun | |

*Ordering constants worth keeping exactly:* the draw is weighted-random with **no memory of the last pick**; repetition is controlled by moods, `whimBeat`, and the heading commitment.

### 6.4 The habit dials (what the Studio's Habits tab exposes)

Grouped as the Studio shows them:
- **Getting about:** Wandering (`wander`), Leaping between windows (`leap`), Dropping on a thread (`rappel`), Swinging on a line (`swing`), Building a hammock (`hammock`), Napping in the hammock (`nap`), Nodding off (`sleep`).
- **Antics:** Drumming (`drum`), Dancing (`dance`), Dancing to music (`danceMusic`), Rolling over (`roll`), Spinning (`spin`), Push-ups (`pushup`), Stretching (`stretch`), Wiggling (`wiggle`), Arms up (`armsUp`).
- **Quiet moments:** Looking about (`look`), Resting (`rest`), Grooming (`groom`), Fidgeting (`fidget`), Scratching (`scratch`), Peering (`peer`), Thinking (`muse`).
- **With you:** Coming to see the pointer (`approach`), Craning at it (`curious`), Staring (`stare`), Glancing (`glance`), **Walking turned toward you** (`walkTurned` — not a weight but a *share* of walking done part-way turned toward you), Greeting (`greet`), Waving (`wave`), Peek-a-boo (`peekaboo`).
Each has a ▶ button that demos it immediately (`pendingDemo` → `runPendingDemo`; demo walks plain/fast so the sim's 10 s window is met).

### 6.5 Body language (personality beyond the repertoire)

Added at the owner's request — "the main thing this spider brings to the table".
- **Carriages** — a walking posture picked per stretch (held 2–7 s) by `pickCarriage`, eased through `worn`: `plain, turned (depth 0.2–0.72), lookingOn (legs side-on, head+abdomen round), sassy, shifty (sneaks), proud, nosy, perky, slouch`. Each is a bundle of `turn, look, pitch, nod, tail, lift, cock, sway, bob, pace, eyes`. `carriageScope`: full at leisure, side-on only for calm purposes (errands), none when urgent (hunt, laser, chase, toy, demo set-up).
- `turnedShare` from the `walkTurned` dial; reference: the owner's spider (affection .86) walks turned 26% → 31–39%.
- **Beats:** *check-ins* on walk pauses (odds from the glance dial + affection; ≈0.6–0.9/min), *double take* (`startDoubleTake` → look at you, away, snap back round to stare; ≈0.08/min, `yawSnap`), `sigh` (≈0.07/min), `nod()`/`shakeHead()`, `wink()`/`slowBlink()`, **head cock** (`cock` spring; `standCock` for stare/curious/glance/greet/look; screen-space, mirror-corrected, ×(1−profile)), palp flicks (`palpNear/palpFar`), `.look` head following idle eyes.
- Mood feeds carriage weights: `moodGlow` (recent happy memory) / `moodShaken` (recent fright).
- A debug switch (`SPIDER_NO_BODY_LANGUAGE`) disables all of it for A/B; with it, flat-walk output must be byte-identical to a build without the feature.

### 6.6 Specific activities — detailed behaviors

(Implement with the posture table of 4.3; these are the behavior rules around them.)

- **Walk / sneak / scurry** — speeds in 4.3; each bout picks a speed, stride, bob and one of four gait styles (plain, bouncy, on tiptoe, lumbering trudge) plus a slow drift of pace; speeds approach by spring.
- **Glance / look** — turns three-quarters toward you; `look` follows idle eyes darting.
- **Turn round** — a real turn on the spot (4.7); `spin` = two back to back.
- **Round a corner** — automatic via path rounding and corner footholds.
- **Wave** — big sweeps from the shoulder, leaning back (pitch 0.16). **Arms up** — both front legs thrown high (greeting or threat). **Greet** — turns right round to face you square on (yaw → 0), big eyes on the pointer, both front legs up and out beside the head in a V, waving a little; triggered by resting the pointer near it, sometimes on click, now and then unprompted (affectionate spiders most), and **Behavior ▸ Say Hi**.
- **Nervous hop** — see 5.5.
- **Stare** — still, turned square on, eyes following the pointer, blinking now and then.
- **Bed on a window** — sleepy ⇒ prefers a window top: walks round its own window to the top or leaps onto one, settles, sleeps with Z's rising (drifting & growing).
- **Drum** — braced low, drums with its front two legs: bursts of quick alternating taps, then three slower beats with both legs together and a body dip on each, abdomen quivering in time, music notes on the beat. Cycle 1.45 s: quick-tap phase for u<0.5, "together" strokes in u 0.5–0.72. Playful, energetic spiders drum most; a click sometimes gets a drum in reply.
- **Roll** — three phases (`rollWindup 0.25`, `rollFraction 0.55`, landing the rest): feet planted, crouching (0.6) and rocking back (pitch 0.22), a shove off the back legs (`rollHop` 9 lift, `rollTip` 0.6 rad tip) into a **ball**. The ball is an egg `ballAlong 20 × ballAcross 17` units; `ballHeight(spin) = √((20 sin s)² + (17 cos s)²)`; `ballLift(spin) = ballHeight + ground − ballCentre.y`. It rolls **without slipping**: `rollSpin −= speed·dt/(ballHeight·scale)` clamped to −2π; speed runs down linearly from `rollPeakSpeed = (2π − rollTip)·r / (0.575·rollFraction·dur)` with `r = (ballAlong+ballAcross)/2·scale`. Lands with a squash (`fatten −4, stretch +2.5` impulse on touch), sits a beat, comes up with `easeOutBack(…, 1.4)`. Only on top of something, and not back the way it just came.
- **Dance** — side-to-side bounce with abdomen going and front legs pumping, to note emotes.
- **Peek / peer** — leans of the *body* about the hips; planted feet stay put and the legs flex; peek: nose-down over the end of a ledge; peer: nose-down at the ledge, then look up.
- **Crouch and wiggle** before a leap (the real jumping-spider tell).
- **Sleep** — then **stretch** up on tiptoe and **shake** itself off on waking.
- **Groom** face, **scratch** abdomen with a back leg, **fidget** with a front foot, stretch each **back leg** behind it, **push-ups**, **wiggle**, **bounce**.
- **Curious** — front legs come up and feel the air when the pointer hovers near, with a "?".
- **Standing, never quite still:** slow shifts of weight, breathing, eyes dart, blinks singly or twice.
- **Eat** — catch held under the fangs by the front legs, chewing (`pose.chew`), prey shrinks as eaten (`eaten = easeInOutSine(u)·0.9`, bitter 0.08).
- **Hop on the spot** (nervous or joy): stages 0–3 as in the posture table; joy leap (charger plugged in) is a real jump (`leapForJoy`).

### 6.7 Thoughts

`think(.kind, for: 3.2)` raises a bubble (suppressed in cinema). `thinkSomething(always:)`: if the talking spider is on and ready, 30% a verbatim verse line, 20% one of your own lines, else ask the model (one "spark" — see 18.1); otherwise by voice: *pictures* → random picture from {heart, hungry, rain, sun, moon, music, star, bug, home}; *phrases* → a random line from the enabled packs + custom lines (if empty and `always` or intelligence, a picture). Packs: **Chit-chat** ("hi!", "boo!", "tap tap…"), **Encouragement** ("drink some water", "take a little break…"), **Spider facts** ("I have eight eyes…"), **Bible verses** (short KJV verses with references; `keepsItsWords` = never rewritten). Own lines: one per line. Contextual pictures: rain cloud when it rains (`raining` triggers a 3.5 s rain thought), sunshine, moon when sleepy, music note when dancing, star, fly when it sees prey, its hammock.

### 6.8 Done when (Stage 6)
- A 4-minute unattended run shows varied behavior with no 1-second changes of mind, no walking backwards, bursts-and-pauses walking, and every Studio Habit dial at 0 removing that behavior entirely while at 1 making it dominate.
- Each temperament preset visibly differs over 150 s (shy hides/rests; hyper scurries/dances; lazy sleeps; grumpy turns its back when poked).
- Tools: the *intent* harness (direction flips, quick re-turns) and the headless sim reproduce the reference numbers in 6.2.

---

## Stage 7 — Air: jumping, falling, throws, landing, being covered

### 7.1 Leaps

- **Gravity** `V2(0, −1950)` units/s² (a world property, also used by silk, toys, prey). Air drag: `vel *= exp(−0.22·dt)` per frame. `maxJumpSpeed = 1250`.
- **`Spider.arc(from p0, to p1)`** — minimum-energy launch: `vMin = √(g·(d.y + |d|))`; if > `maxJumpSpeed` ⇒ out of range (nil). Otherwise `arc(from,to,speed: min(vMin·1.06, maxJumpSpeed))` which returns the **flatter** of the two parabolas that land on `p1`: `dx=|d.x|; raw = v⁴ − g(g·dx² + 2·d.y·v²)`; if raw<0 nil. A jump either looks like a jump or is never attempted — do **not** pick a flight time and clamp the speed afterwards (that broke the equation and made long jumps fall short).
- **`ballistic(from,to,underRim)`** also checks the screen's top rim (a launch that would knock its head on the rim and drop back is pushed flatter/harder, or refused) and, in the tank, `leapBlocked` (an arc passing >6 units through a solid outline is out of reach).
- **`bestJumpSpot(from, exclude, behind)`**: `sampleSpots(spacing 40)`; for each spot `d` between 70 and 680 (a straight drop with `|dx|<60` and `y < p.y − 20` counts from 28); `score = kind.appeal × appeal(point, kind) × remap(d, 70→680, 1.25→0.45)`; ×0.03 if outside the box; ×0.18 if it's the `exclude` loop; ×0.3 if the current loop; × `behind` if behind the walking direction; ×`remap(dist to cursor, 0→500, 1.9→0.9)` when playful & cursor within 700; requires a valid `ballistic` and `launch·normal > −0.15` (cannot leap through its own surface); ×`randRange(0.55, 1.45)`; pick randomly among the top 4.
- **Sequence:** `turnTo` the target side → `crouch` (with the pounce wiggle, `wag` after u>0.3) → `launchPendingJump()` → air. A launch pointing into the surface it is on becomes a let-go-and-fall with a push away from it. A low window is "a step down, not a jump": anything below counts as a drop however short; from any underside it as often as not simply lets go.
- **In flight:** legs pose (push-off: everything driven back and down for 0.16 s, then stretched `1.15×` jump / `1.05×` fall with flutter `wobble·1.6/2.0`); heading = pitch into the arc, clamped ±0.85 rad (never rolls past ≈50° — "or it reads as tumbling"); `facing = sign(vel.x)`; a thrown spider adds `sin(t·9)·0.18` wobble; tumble after a hard bounce (`tumbleVel` decays `exp(−1.1·dt)`, rights itself when a landing is near).
- **Landing:** the last stretch turns it to meet the surface feet-first (even upside-down under a window): `landingReach = clamp(1 − dist/range, 0, 1)` with `range = max((landing ? 130 : 70)·scale, speed·0.22)`; facing set when `w>0.45`; `headingTarget = fh + angleDelta(fh, surfaceAngle)·smoothstep(landingReach)`; legs reach to `stand = rest.foot + (±3, −3)`; touchdown squash, `landDrop`/`landHold`/`landAbsorb`; then a beat to get its feet under it.
- **Grabbing a surface:** `nearestSpot(within: max(18·scale, speed·dt·0.8))` excluding `launchLoop` for 0.28 s; only if moving toward it or slow enough; an underside is only grabbed from below or slowly. A **pounce** grabs nothing until near its mark (`<34·scale`) or past it falling or `airTime > 1.6`. `noAttachFor` (0.06 s after a throw) stops instant re-grab.
- **Bounces off screen edges** (`bounceOffScreens`; `restitution = lerp(0.28, 0.72, bounciness)`), unless flying home or fully off.
- **Falls** shoot a **rescue line** if it drops too far (`planFall`); a rescue line caught at speed turns into a swing, so a bad leap can chain into another.

### 7.2 Throws
5.3. Soft toss ⇒ planFall(lineUp) — a line from the ceiling catches it. Hard ⇒ fly/tumble/bounce. Speed capped 2700.

### 7.3 Cursor pounce
Crouch → aim at the cursor (`aimPounceAtCursor`) → flight; while pouncing, passing within `30·scale` of the pointer segment ⇒ `catchCursor()` → mode `clinging`.

### 7.4 Joy leap (charger plugged in)
A real leap — up off its legs and down onto them; on a wall or underneath a window it keeps every foot where it is and bobs and wiggles on them.

### 7.5 Banner jump (notification pop-up)
Jumps right up in the air if on top of something; a start where it clings if on a side or underneath; then stares up at the banner. Volume/brightness changes only make it *look* up.

### 7.6 Being covered (windows coming over it)
- Only a **window's** edge can be covered; screen rim, taskbar-equivalent and menu bar never are.
- `covered` = its edge segment is blocked at its position (`!seg.isOpen(at: t)`), or `bodyCovered` = `!map.isVisible(pos, depth)` (a window that only overlaps the body counts). If covered for > 0.05 s and `t > escapeUntil` ⇒ `escapeOcclusion()`: sets `escapeUntil = t + 2.0` (an escape is **never restarted while under way** — the check runs every frame and restarting froze the spider), clears queues, `startled.velocity = 6`. Then: fire a line straight up and haul itself double-time to whatever is above (window underside, bar, screen top), **or** let go and drop (often shooting a line on the way down to swing out on); from the floor it always goes up; if neither is possible, leap for the nearest clear spot. It **never walks along the covered edge** to the open part.
- It never *takes hold* of a window where another hides it: no dragline fastened to a covered stretch, no landing on a window edge unless all of it is clear of windows in front.
- On a line: climbs straight up out of the way. In the hammock: windows do **not** matter (rule 9).
- Carried off-screen by a window: no alarm; carries on 10 s then `climbBackOnScreen()`.

### Done when (Stage 7)
- 1000 random leaps in a synthetic desktop: ≥ 95% land within 12 units of the target; none start through their own surface; long jumps are never silently short.
- Throwing at every screen edge/corner never leaves it lost off-screen; "Bring to the Middle" always recovers.
- Dragging a window over the standing spider: it is out from under within two polls and never "perched on the glass".

---

## Stage 8 — Silk: lines, rappel, climb, swing, mantle, hammock

### Goal
Everything the spider does on a thread, with the owner's hard-won realism rules. This is the most intricate animation stage after legs.

### 8.1 Line state

`webActive`, `webAnchor` (world), `webLen`, `webLenTarget`, `webAngle`, `webAngleVel`, `webStyle {hang, swing}`, `webPlan: [WebPlan]`, `lineOrder`, `lineTop`, `floorLen`, `hangOff`, `rope: SilkRope` (14 segments, head pinned at the anchor, tail at the spinnerets). `WebPlan` steps:
```
descend(L)   pay out to length L
linger(sec)  hang about for this long
climbHome    haul back up to whatever it hung from
toFloor      all the way down and step off
swing        work up a swing and let go
jumpOff      spring off the line to somewhere near
swingOff(L)  the top is gone: pay out to L, swing up and let go
```
Dropping onto a thread it **decides then and there what the thread is for** (a short list of intentions) and works through it: down to a chosen height; a while hanging (a bounce on arrival if it's that sort, the odd shift of weight that sets it swaying, a note or sparkle, a look about; it pays out line to come and see a pointer waiting underneath); sometimes a second look further down or back up; then one way off — hauling back up, all the way down to the floor, working up a swing, or springing off to something near. It does not change its mind every few seconds and it does not turn round on the line to show its other side or face. It turns **end for end only on purpose, to face up the line for a real climb.** A window sliding in front of it, a meal or the red dot turning up, or a scroll order cut the plan short; a scroll order is followed through (8.5). Pleased on a line, it bounces on the end of it and kicks its free legs.

### 8.2 Hanging (owner's rules, 2026-09-25)
- Head directly **below** the body (side-on, never beside it); line runs up from the spinnerets.
- **Only the back four legs hold the silk** above the abdomen: third pair out to the side and in to it just over the tip; fourth pair reaching up along the abdomen to hold it higher.
- **Front four hang free**, each foot a weight on the end of its leg: swing with the body, trail when it moves, settle when it stops, stir now and then. "Dangle a little more freely but shouldn't just be floppy" — loose, independently drifting, lagging the body a touch, knees bent. They can also pump a swing.
- Going down, it pays the line out through its hind feet, which take turns drawing the silk from the spinnerets, while the first pair reach down for whatever is below.
- Leaving a ledge: dab the line down right by its spinnerets and swing down head first about them; off the top of something (nothing over the drop) it steps off the edge on its dragline and lets the line take it a short way down first (`rappelAfterCatch`).
- The held stretch of line is drawn **inside the sprite between the far legs and the body**, so far feet read as behind it and near feet in front (`pose.thread`).
- A leg swinging round a hip goes round at arm's length with its knee turning over as a real one does, **never folding in through the hip** (`Spider.roundHip(from, to, hip, e, turn:)`).
- Feet hold the line where it really lies and stay on it as the body bounces on the end of it. The rope is updated **before** the legs each frame while on a line. Every leg keeps its length however fast it reaches.
- The real IK (`kneeIK`) is used only for legs holding the line; bend side chosen outward from the thread; each foot pulled back along the line to the nearest reachable point.

### 8.3 Rappel, drop, rescue
- `dropOnWeb()` from a ledge: shoot/dab the line, step off; `canRappel()` own-initiative only from an underside (`facing == .down`) and `pos.y − screenMinY > 150`; if the user asked (scroll) anywhere with room works.
- Weight: `webAngle = atan2(r.x, −r.y)`, `webLen = max(24, |r|)`; dragline catch when the line takes its weight.
- `planFall(from:lineUp:)`: a rescue line from a ceiling above.
- Swing launches: `launchSwing()` after `shoot` (one leg pointing the way) — see 8.6.

### 8.4 Climbing (owner's rules, 2026-09-26)
- To climb it **turns end for end** — head first, **rolling about its middle** (weight under its grip), not swinging round on its spinnerets: it draws the line in to its belly, front legs fold in and reach up.
- **Hug the silk:** the silk runs right along its belly, tucked under the edge of its abdomen, as close to its middle as a line on the outside of a spider can be; the body hangs back a touch from its front legs with its weight under them. Front two pairs reach up the silk past its head, hind two pairs down it past its abdomen, knees bent out from the thread.
- **Hand over hand:** body rises in pulls as each front leg heaves. Every foot on the line keeps its hold while the body goes past it, then lets go, lifts off and reaches on up for the next hold — **no foot slides along the silk**.
- **The loop:** hauled-in silk hangs in a loop from the spinnerets to the line below its feet (`thread.tail`). The owner likes this; keep it.
- **Climbing never means walking up the thread as if it were a hard edge** ("doesn't make physical sense").

### 8.5 Mantle: pulling up over a lip, stepping down onto one
- **Over the top** (arriving at the top of what it hung from): front feet take hold of whatever the line hangs from, it climbs up onto it and steps its other feet across — never "landing" there. Coming up the face of something it stepped off the top of: the line runs up over the lip; front legs reach out over the top, pull up until the waist is at the lip, tip forward over it belly first between them, hind legs (which have been pushing on the silk) come up last, then stand. Scripted (`Mantle`, "Over the top, and down onto it").
- **Down onto a ledge** (head-down hang): front legs reaching down take the ledge first, the body comes down onto them and pitches over belly first, hind legs let go of the silk last and step down.
- Once it stops a while or sets off back down, it lets go with its front legs and swings back round about the hind legs' hold to hang.

### 8.6 Scroll orders (owner rule: obey without reversing)
`LineOrder {up, down, drop}`; `scroll()` → `obey()` (5.4).
- Scroll **up** on a line: climb all the way up and onto what the line hangs from (over the lip if it stepped off a top).
- Scroll **down** on a ledge: rappel about halfway to whatever is below and hang (`.drop`); it may go about its business after a long hang.
- Scroll **down** while hanging: all the way down to the next standable ledge and step onto it.
- **Anything that sets `webLenTarget`/`webPlan` (pointer curiosity, plan steps) must not override an active order.** One swipe (trackpad gesture incl. momentum, or a quick run of wheel clicks) = one order.

### 8.7 Swinging
- Pick an anchor ahead (window corner, bar, screen top); rear up and **fire a line** (`shoot` activity, one leg pointing the way, `shotProgress`), push off, swing on it, reeling in to gather speed. If the push-off didn't make a big enough arc, or it starts from a plain hang, it **pumps** pass by pass — kicking its legs and shifting weight in time with the motion — until the arc reaches `swingTargetPeak`. Then it lets go near the top of a swing and flies, or grabs whatever it swings past. A rescue line caught at speed becomes a swing.
- Hangs like a weight on a string: in line with the thread, head to the ground, tilting with the line at the ends of the arc and trailing it a little through each pass. It keeps the **same side to you for the whole swing** (turning to face its direction on every pass made each arc end a somersault).
- Rope edge case: a line whose anchor is itself inside the screen-edge margin must not apply the sideways "snag" (it pinned the spider still or made it jitter); the snag applies only to lines hung from well inside the screen; the widest-swing limit is a gentle push back, not a bounce.

### 8.8 The hammock
Model (copy exactly): `HammockStyle {sling, pouch, tangle, cradle}` with
- `sagShare` (middle sag as a share of the corner height): 0.42 / 0.66 / 0.50 / 0.34
- `strands`: 7 / 9 / 6 / 6
- `give` (extra sink under weight): 10 / 16 / 8 / 12
`Hammock { left (which top corner), rect, progress 0…1, damage 0…1, style, load 0…1, seed, loadU?, sway, drape[] }`.
- `wallAnchor = (left ? rect.minX+2 : rect.maxX−2,  rect.maxY − rect.height·0.62)`; `ceilingAnchor = (left ? rect.maxX−4 : rect.minX+4, rect.maxY − 2)`; `sag = rect.height·style.sagShare`.
- Centre line: quadratic Bézier wall→ceiling with control point `(a+b)/2 + (0, −(sag + drop + load·give)·2)`. Under load, a local dip `p.y −= load·give·1.6·bell·(1 − 0.4·strand)` with `bell = smoothstep(1 − |u − (loadU ?? bedU)|/0.32)`; sway `(sway, |sway|·0.12)·sin(πu)`. `bedU` = parameter of the lowest point, clamped 0.15…0.85. `bed = point(at: bedU)`.
- `strandsLaid(progress, of: strands)`: 0 below 0.1; 1 up to 0.30; then `1 + floor(remap(progress, 0.36→0.88, 0→strands−1))`. Each newly laid strand starts **taut** and drapes to its sag over **2.4 s** (`drape += dt/2.4`).
- `drawFrame` = rect plus `0.8·height` below and 30 on the open side.
- **Build sequence** (all ordinary walking/jumping and one fastening pose on the surfaces it always uses — "nothing glides"): pick a top corner; back its abdomen onto the side wall and stick the first thread down with a few dabs (`fasten` activity: dab = 0.5+0.5·sin(3πu)); climb the wall, hop across the corner onto the underside of the menu bar (or the ceiling/top edge on Windows), walk out along it paying out silk behind it from wall to spinnerets, taut, until the far anchor and stick that end down; the strand sinks into its sag over 2.4 s; back the other way — along the underside, a hop down to the wall, down to the first anchor — laying the next strand; cross and re-cross until a sling of strands hangs there; then step onto the silk itself (the sling is ground to its feet like any ledge; feet plant on strands and step), in along the sling to the middle, a few steps back and forth tying cross-ties off, test with a bounce.
- Looks: loose and stringy — uneven strands each hanging a little slack, loops of silk drooping beneath, slack cross-ties, tufts where it's stuck down, the corner itself left open behind it. Four kinds each a little different (seeded).
- **Napping:** climbs in and curls up (`stretch 0.86` when curled): every leg drawn in tight (`tuck = hip + reach·0.28 + (±3, 2.5 + k%2)`; front pair folded over the face), breathing (`wobble·0.5`), seen through the silk (hammock window above the spider). Lazier spiders nap more. Going to bed later is the same walk in along the silk; getting up is a walk out to the wall end before stepping off.
- **Rules (owner, 2026-10-16):** windows never affect the hammock; only the pointer moved over it (within 40·scale of it and faster than 30 pt/s) wakes it, and it gets up gracefully (`leaveNest(startled:false)`: walks out along the silk to the wall, stretches, shakes). It falls only if the hammock is destroyed (fully wiped / `clearHammock`) or `hammock == nil` while nesting; a partial wipe (damage > 0.3) also gets it up gracefully. Don't add new `startled:true` triggers.
- **Wiping:** moving the pointer across it tears it down (`wipeHammock(at, movement)`, movement capped at 80); a couple of good swipes clear it; a sleeping spider tumbles out startled. A half-made one goes with a single wipe.
- **A hammock that isn't being built doesn't exist:** nothing is drawn until the first strand is laid; an unfinished hammock nobody is working on fades away; menu offers **Clear the Hammock** whenever any silk exists.
- Interruption (a window over the corner, a fall, being picked up): what's spun stays; it comes back to finish. Persisted (kind and all) across restarts. Mend when damaged. In a film it's abandoned.
- Menu: **Build a Hammock**, **Nap in the Hammock**, **Clear the Hammock** (under Behavior).
- The hammock overlay is drawn above every window and hangs from the screen rim/bar, which windows never block.

### Done when (Stage 8)
- Rappel, hang, turn-to-climb, climb, top mantle, step-down, swing pump and release, scroll orders — each captured as film strips and compared to the Mac build at close range. Check: the body's centre stays under its grip; feet stay on the drawn silk; legs keep their length; no leg jolts versus a baseline.
- A full hammock builds in all four kinds, drapes over 2.4 s per strand, bears the spider, and tears on wipe.

---

## Stage 9 — Peek-a-boo

### Goal
The game where the spider hides behind a window edge and bursts out at you.

- Triggers: when someone is about (pointer within 520 and active <20 s, not already watching it) and an edge is near, each decision `chance(min(1, lerp(0.03, 0.14, playfulness)·hw(peekaboo)))`; or asked (**Behavior ▸ Peek-a-boo**, `wantsPeekabooUntil`): if no edge to hide behind where it is, it leaps off to find one (`goHideSomewhere`). `startPeekaboo(reach: asked ? 600 : 260)`.
- It is drawn above windows but **the part inside a window in front of the window it stands on is cut out** (`pose.hiddenBy`), so it really goes *behind* that window. Two front feet are shown as little dots gripping the edge (`peekGrip`).
- Sequence (`peek` stages 0…): creeps up to the edge → slips behind → waits → **bursts out** (front legs thrown up, eyes on the pointer; `out` posture: lift 3, pitch 0.2, legsFree) → back behind and again, **two to four times**, finishing with a happy wiggle. The "behind" posture: crouch 0.3, lift −2, pitch −0.1.
- The peek-a-boo check is skipped when the pointer-interest branch fired. The covered-escape check is suppressed during peek-a-boo (`activity != .peekaboo`).
- Occlusion rules in 3.1/7.6 apply: the rim, taskbar and bars are glass in front of everything; windows are only hiding places.

### Done when
- On the Mac, peek-a-boo is filmed as a strip of moments with a window drawn over; match the timing and the behind/burst rhythm.

---

# PART E — THE WORLD IT SHARES

## Stage 10 — Prey, feeding and wildlife

### Goal
Things to hunt. The spider watches, stalks, pounces, carries off, and eats; creatures behave like creatures.

### 10.1 Creature kinds

| Kind | Flies | Climbs | Takes off | Armoured | Bitter | catchRadius | mealTime (s) | nourishment | clearance |
|---|---|---|---|---|---|---|---|---|---|
| Cricket | | | | | | 22 | 5.5 | 0.55 | 4 |
| Worm | | | | | | 24 | 6.5 | 0.60 | 2.5 |
| Fruit fly | ✓ | | | | | 20 | 3.2 | 0.30 | 3 |
| Moth | ✓ | | | | | 26 | 5.0 | 0.50 | 2.5 |
| Beetle | | | ✓ | ✓ | | 22 | 7.5 | 0.70 | 3 |
| Ant | | ✓ | | | | 17 | 2.4 | 0.25 | 2.5 |
| Mosquito | ✓ | | | | | 17 | 2.2 | 0.25 | 4.5 |
| Ladybug | | ✓ | ✓ | | ✓ | 19 | 1.4 | 0.00 | 2.5 |

`wariness` (next to a cricket = 1): moth 0.45, ladybug 0.6, mosquito 1.5, others 1. Units: world px at scale 1 for radii. `catchRadius` = how close the spider's mouth must come.

`Prey { kind, id, scale, pos, vel, heading, facing, state (loose | caught | eaten | squashed), noticed, spurned, onSurface, tucked, held, eaten (0…1), … }`. Creatures live in the **prey window** (screen-sized, shown only while something is out) and the same window draws toys.

### 10.2 Creature behaviors

- **Cricket** — released onto a ledge some way off; sits, twitching its antennae; hops away when the spider closes in; a frightened one as often freezes as hops.
- **Worm** — inches along, a little faster when something big is near.
- **Fruit fly** — let go in the air; jittery random walk, perching on edges to clean itself, taking off again when the spider gets close. Caught when it comes within reach of a stationary or snatching spider (snatching whatever its fangs pass in the air).
- **Moth** — slow and floppy; **drawn to the pointer like a lamp**: circles it until it tires, then rests a long while on a wall wings folded back like a roof. Dozy: slow to notice anything coming.
- **Beetle** — plods, never runs. Something walking right at it makes it shut itself in its shell (fangs skid off). The spider creeps up from well off or, if it clams up, keeps quite still beside it until it comes out. Knocked about enough, it opens its wing cases and blunders off to another ledge.
- **Ant** — quick, tireless, climbs anything: round corners, up window sides, underneath. It hardly sees, but feels anything big walking on its window and turns tail. Chasing is hopeless: the spider lies in wait in its path and snaps it as it walks into its jaws, or leaps on ahead and waits.
- **Mosquito** — hangs in the air with a wobble, then darts off dead straight, likes to pester the pointer. Only catchable while hanging still: the spider watches and strikes then.
- **Ladybug** — always climbing up any wall to the top of things, opens its shell and flies. Tastes horrible: the first is caught, tasted, spat out (none the worse); with *Learn From Experience* on the spider remembers and afterwards only watches them.
- **Noticing**: a creature notices something big moving fast nearby at once, something creeping up slowly not until very close.
- Surface movement: crawlers use the same `SurfaceMap` loops as the spider (ants/ladybugs also corners, sides, undersides); fliers have air motion that perches on edges. A creature that loses its surface (window closed) falls to whatever is below.

### 10.3 The hunt

Triggered from `think()` when `quarry()` finds an unspurned, noticed, loose creature within reach rules. Sequence:
1. Drops whatever it was doing (idle habits dropped; a walk too unless it is the hunt's own; checked every frame while a creature is within 300·scale).
2. Watches the quarry; walks round its own window to it, or leaps to whichever ledge gets it nearest.
3. Walks in; **stalks the last stretch low and slow** (`sneak`).
4. **Pounces** once close and the prey sits still: `crouch` → launch aimed at the prey (`huntPounce`, `pounceMark`); the aim is re-targeted during the crouch while the prey is below and moving (`flight = (−90 + √(90² + 2g·fall))/g`, `aim = q.pos + q.vel·(remaining crouch + flight)`); while airborne `snapAtPrey(reach: 6)`; **a pounce is aimed at the prey, not the furniture**: it sails past window edges and grabs only once at its mark or past it.
5. **Catch:** state `caught`, held under the fangs by the front legs. Often carried to the end of its ledge (`mealCarry`, ≤10 s) before eating. `eat` for `mealTime × 0.9–1.15`; prey shrinks as it is eaten. Laden speed ×0.75.
6. **Leavings** (Traces, 12): wings, two halves of a shell, left lying; the spider kicks them along as it walks into them.
7. A good meal leaves it visibly happier (grin, sparkle, hearts, wiggle) and **well fed** for a good while (`fed`). Hunting interest is wiped out if a creature is let go (re-noticed).
8. Hunt rate adjusts with `learned.prowess` and `hunger` (tank only).

Constants: notice reach `75·scale·(1 + prowess)` for a close snap; `spurned` creatures are ignored; wake on a caught fly; up to **4** things loose at once.

### 10.4 Feeding UI
- **Feed** (menu / panel page "Feed"): release a Cricket, Worm, Fruit Fly, Moth, Beetle, Ant, Mosquito or Ladybug. Ground creatures drop in onto a ledge some way off; flies are let go in the air. Creatures can be picked up and moved (drag/flick ⇒ they drop onto whatever is below, the spider's interest renewed).
- Creatures released inside a Box appear inside it.

### 10.5 Wildlife (let creatures wander in)
- Setting `wildlife` (off by default) with `wildFrequency` slider ≈ one every 1.5 h → one every ~10 min, never on the dot. Kind chosen by `PreyKind.wanderingIn(night:raining:)` odds: fruitFly 3, ant 2.5, beetle 1.3, moth (night 5 : 0.7), mosquito (night 2.5 : 1), ladybug (night 0.2 : 1.8), cricket (night 2 : 0.8), worm (raining 5 : 0.3). Ants come in a little line. Fliers enter through the side of the screen; walkers come out of a crack.
- The spider must **spot them first** (sooner if close and moving, hardly at all asleep). Unspotted creatures go about their business; after a few minutes anything uncaught flies off the side or slips into a crack.
- Never while nobody is at the machine (idle), while the spider is in the habitat (it has its own), or while a full-screen app has the desktop; never more than a few at once.

### 10.6 Done when
- Each of the 8 kinds is released and hunted with its signature behavior (moth around the pointer; beetle shell; ant ambush; mosquito strike-when-still; ladybug taste-and-learn).
- Film strips of cricket, worm and fly hunts (the Mac `film --hunt`) match in structure: watch → approach → stalk → pounce → meal.

---

## Stage 11 — Toys and the laser

### Goal
Pointer-driven play. **Owner's rules:** toys work through the pointer like the laser; picking one puts it in your hand; a click deploys it; the pointer is "for playing" while a toy is on it.

### 11.1 Picking and putting away
- **Play ▸ Toys** (or Toys ▸ in the right-click menu): Laser Pointer, Ball, Feather, Bell, Wind-up Bug; **Put Away**. Only one hand toy at a time. **Right-click or Esc** while a toy is on the pointer puts it away (Esc is a *registered hotkey active only while something is on the pointer* — a permanent global Esc would be stolen from every app); right-click on a toy you've put down puts it away.
- While a toy is on the pointer, clicks and scrolling don't reach apps underneath (a **catcher window** rides under the pointer; hidden over the spider so it can still be picked up), until you put the toy down or away.
- **Laser:** the red dot sits right on the pointer the whole time. The spider drops everything and races after it (along its edge at a scurry or with a leap to the nearest spot), pounces and pats; put away, it looks about for it, puzzled.
- **Feather:** dangles on its string (`tether` 105 px) permanently from the pointer, like a wand toy, trailing behind; the spider leaps at it and sometimes gets hold of it and hauls it down on the string.
- **Ball, Bell, Wind-up Bug:** picked, it rides on the pointer in hand (the spider waits under it, eyes on it). Click puts it down there; drag + flick throws it; the bug is set down wound-up and scuttles off. That click is taken by the toy (no selection box on the desktop). Once down: drag to throw again, click to poke, or press its button again to pick up. The bell jingles when knocked or shaken (out loud too, quietly, unless **Bell Sound** is off — setting `toySounds`).

### 11.2 Toy physics (one physics body for all toys; kind = a set of numbers)

| Kind | radius | restitution | mass | edge drag (drag/s, brake px/s²) | gravity share | air drag/s | rolls | tether | lure | bat-loft range (rad off the surface) |
|---|---|---|---|---|---|---|---|---|---|---|
| Ball | 7 | 0.72 | 1 | 0.6 / 30 | 1 | 0.12 | ✓ | 0 | 1.0 | 0.15–0.7 |
| Feather | 9 | 0.05 | 0.35 | 6 / 220 | 0.09 | 2.6 | | 105 | 1.15 | 0.9–1.3 |
| Bell | 6.5 | 0.42 | 1.7 | 0.9 / 40 | 1 | 0.12 | ✓ | 0 | 0.9 | 0.05–0.35 |
| Wind-up Bug | 7.5 | 0.22 | 1.3 | 4 / 160 | 1 | 0.12 | | 0 | 1.1 | 0–0.15 |

Feather flutters (drifts side to side, tipping). Bell chime 1. Bug winds up (walks off by itself until it runs down).
The toy falls, bounces off and lands on the **same window edges, taskbar and screen rim the spider walks**, rolls or slides along them, tips off the end of a window and bounces back off a wall. An `anchor` means it sits on top of an edge; `roll` = speed along it; `spin` for drawing; `knocks` counter lets the spider notice new knocks.

### 11.3 Spider behavior around toys
- While playing it goes for the toy like the dot: the playful at once, the lazy when they get round to it; never tires of it while you play. A timid one looks a new toy over from a safe distance first and jumps out of the way of one rolled at it; a bold one traps it with its legs. Left lying about, a toy still gets batted about now and then (`pickToy()`, `toyPlay` stages: `play` …), until it tires of it. Visitors join in. With learning on it comes to have a **favourite toy** (`toy.<kind>` memory name).
- **Pats**: the spider bats a toy up at `batLoft` angles; **Tow**: instead of a pat it sometimes turns its back on a lying toy beside it, dabs a line onto it and walks off towing it (speed ×0.7); pulled over the end of a ledge the toy swings on the line, and a heavy one snaps it (a Trace).
- Toys are never "prey" (never hunted as creatures).

### 11.4 Test hook
A toy test: pick each toy in turn (memory off), throw it now and then as if by the user, print what spider and toy are up to every 2 s.

### Done when
- All four hand toys + laser work with real mouse input; toy physics matches the table on the real edges (ball rolls off a window top and bounces on the next ledge).

---

## Stage 12 — Traces

### Goal
Marks the spider leaves on the desktop that fade by themselves. Off by default (**Behavior ▸ Leave Traces**). Only your own spider leaves traces, never a visitor.

### 12.1 Kinds
- **Silk strands:** now and then a leap trails a line from the ledge it left, stuck down where it lands; the rappel line is often left where it stepped off; a swing it lets go of, or a line it jumps off, is left hanging loose. Strands are **pinned to the real edges they join** and are the same rope physics (Stage 1.4) as the dragline: drag a window and the strand rides along, stretching or sagging; pull the two apart and it snaps, each end left hanging; close the window or bring another in front across it and it tears there. The pointer brushes it: a slow push bends it aside (`SilkRope.push`), a quick swipe snaps it, a sweep tears a web.
- **Little webs** in sheltered spots: a sheet of criss-crossed threads in a corner where the floor meets a wall (or a Dock side), or a tangle hung under a window it hangs from. It walks over, backs up to the spot and dabs the threads down (`webJob`/`webSite()`).
- **Meals carried off:** leftovers (a pair of wings, two halves of a beetle's shell) lie where it ate; they **ride along with a window**, fall when it goes, land on whatever is below, and are kicked along as it walks into them; a flick of the pointer knocks a husk off its ledge.
- **Toys hauled off:** 11.3.
- Flies that blunder into any silk are stuck struggling a while; the spider feels it (a caught fly wakes it) and comes for them.

### 12.2 Rules
- Drawn only — in a click-through window under the spider; nothing on the real desktop is touched.
- **Most at Once** (`traceLimit`): 3…60, oldest fade as new come; top = Unlimited (everything stays until it fades on its own). **Tidy Up** clears all. Turning the setting off clears whatever is out.
- Needs `config.webs`; not in a box (`!confined`); `leavesTraces`.

---

## Stage 13 — Memory: growing up

### Goal
A slow, bounded personality drift from what has happened. "It nudges the same personality sliders every choice already reads." On by default; **Learn From Experience** toggle (`learns`) off ⇒ exactly the Studio's personality (memories kept for later); **Forget It All** wipes. A visitor, the Studio preview and tools have no memory.

### 13.1 Experiences
`Experience` = petted, greeted, company (by the minute), carried, thrown, startled, chased, played, fed, huntWon, huntMissed, alone (by the minute). Each has an **imprint**: feeling half-life (`mood`), lesson half-life (`lasting`), `rate` (how much of the way to a settled lesson one measure takes), `comfort` (liking of the place).

| Experience | mood half-life | lasting | rate | comfort |
|---|---|---|---|---|
| petted | 15 min | 10 d | 0.05 | 0.6 |
| greeted | 10 min | 7 d | 0.03 | 0.3 |
| company | 20 min | 7 d | 0.04 | 0.3 |
| carried | 10 min | 5 d | 0.03 | 0 |
| thrown | 15 min | 4 d | 0.04 | −0.3 |
| startled | 12 min | 3 d | 0.03 | −1 |
| chased | 10 min | 3 d | 0.03 | −0.4 |
| played | 20 min | 7 d | 0.04 | 0.4 |
| fed | 30 min | 5 d | 0.03 | 0.8 |
| huntWon | 20 min | 10 d | 0.05 | 0.4 |
| huntMissed | 10 min | 4 d | 0.03 | 0 |
| alone | 30 min | 5 d | 0.03 | 0 |

### 13.2 What an experience teaches (`feels(personality)` → `TraitShift`)
`TraitShift` has the six sliders plus `prowess` (sureness on a hunt) and `roaming` (how much it explores). Per experience (value per full measure):
- petted: affection 1, bravery 0.6, curiosity 0.3, laziness 0.15, roaming −0.3 · greeted: affection 0.8, curiosity 0.5, bravery 0.4, roaming −0.2 · company: affection 0.5, bravery 0.5, curiosity 0.3, roaming −0.4 · carried: bravery 0.4, affection 0.3, curiosity 0.1
- thrown (`joy = (bravery + playfulness) − 1`): playfulness `0.1 + 0.6·max(joy,0)`, energy `0.3·max(joy,0)`, bravery `−0.1 − 0.7·max(−joy,0)`, affection `−0.4·max(−joy,0)`, roaming `0.2·max(−joy,0)` — the same fling is a thrill to a bold playful spider and a fright to a timid one
- startled: bravery −1, curiosity −0.3, laziness −0.2, energy 0.1 · chased (`joy = 2·playfulness − 1`): playfulness `0.4·max(joy,0)`, energy `0.3·max(joy,0)`, bravery `−0.2 − 0.8·max(−joy,0)`, curiosity `−0.3·max(−joy,0)`, roaming `0.3·max(−joy,0)`
- played: playfulness 1, energy 0.5, affection 0.3, laziness −0.4, bravery 0.2 · fed: laziness 0.3, prowess 0.2, affection 0.2, energy −0.1 · huntWon: prowess 1, bravery 0.3, energy 0.2 · huntMissed: prowess −0.6, bravery −0.1 · alone: roaming 1, curiosity 0.4, energy 0.2

### 13.3 Rules
- No trait moves more than **a fifth (0.2) of the way** from the Studio value (`TraitShift.most`). The Studio's personality is never changed.
- Each memory has a **feeling** that passes within the hour and a **lesson** that builds slowly and fades over days. Time with the app closed counts toward forgetting but only up to **three days**.
- A shy spider stroked every day grows easier about the pointer while staying shy; a run of frights leaves it warier for an hour or so; good hunts make it surer; hours alone make it a wanderer; favourite spots (place memory with `comfort`) pull it back.
- `learned.lean(habit)` also leans habit weights; `moodGlow`/`moodShaken` weight carriages.
- Also remembers **places** (favourite spots) and **prey** (ladybugs taste bad), and toys (favourite). Saved in settings (`memory` key); saved every 60 s if dirty.
- The Spider page of the panel shows a line on how it has been shaped lately; **Forget It All** resets.

---

# PART F — SENSING THE MACHINE

## Stage 14 — Sensing the machine

### 14.1 Cinema manners (full-screen video, maximized-as-full-screen)
- Trigger: when any app takes a whole display (see 2.1 and 2.7), or a window fills the visible frame within `maximizedSlack` = 24 units (tiling margins) **and is the front window on its screen** (`WindowTracker.fills(frame, visible:)`).
- On that display only a **floor and a ceiling** exist: no walls, menu bar, dock or windows.
- Behavior: walks to the nearest corner of the floor (or ceiling — it hangs as usual, head turned to the picture), lies down facing the picture with head tipped right up (`watch` activity: floor lift −5, crouch 0.34, pitch 0.12; elsewhere lift −1, pitch 0.08), gaze drifting with whatever happens; now and then stretches a leg a short way, grooms, or glances your way; **does not leap, swing, spin silk, hunt or go to its hammock**; ignores the pointer; only after a very long while nods off. Walk pace ×`cinemaPace` 0.6. Thought bubbles are suppressed. Seat choice: nearest of the four floor/ceiling corners (24 units in) or the hammock door if finished.
- When it ends, it carries on as before (`cinemaSince`, 4-poll hold-off).
- A spider on a window that grows to fill the screen goes with it and ends on the screen's rim (never pushed off the bottom or left on the window's underside). With another window in front the screen is ordinary again but the maximized window has no edges of its own.
- **Browsers**: a full-screen browser showing a page is *not* cinema if the page is being climbed (Stage 18.2); showing a film (most of the picture changing, look after look) it is.
- A window is counted as full-screen when it covers the display, or all but the strip a notch takes.

### 14.2 Power: Low Power Mode and the charger
- **Low Power** (the spider's own): sleepy and slow, 30 Hz clock (half the frames), `drowsy` 0…1 slows decisions, increases rest/nap, reduces play. Follows the machine's mode (Windows: **Battery Saver** / `PowerRegisterForEffectivePowerModeNotifications`), but the user can switch it on while the machine isn't in it or off while it is (that asks first since it costs battery; lasts until the machine leaves the mode). Setting key `lowPowerOverride`.
- **Feel the Battery** (`feelPower`): entering the machine's low-power mode ⇒ the spider's. **Plugging in the charger** perks it up: it crackles with lightning (`emote .charge`), and on top of something jumps for joy (7.4). Detect only the moment it happens, not at launch. Windows: `GetSystemPowerStatus.ACLineStatus` + `WM_POWERBROADCAST` / `GUID_ACDC_POWER_SOURCE`.

### 14.3 Weather outside ("Notice the Weather", `feelWeather`)
- Every **20 minutes** (and once at start), look up approx. location from the internet connection, then Open-Meteo: `https://api.open-meteo.com/v1/forecast?<lat/lon>&current=precipitation,weather_code,wind_speed_10m,is_day,temperature_2m`. Report `(WMO weather code, wind km/h, isDay, temperature °C)`.
- When it rains: rain is on its mind (`raining`): a 3.5 s rain thought; **Rain on the Screen** (`showRain`) adds faint streaks across the desktop while it rains.
- The habitat's **Weather ▸ Like Outside** mode follows this via `WeatherKind.outside(code:…)`.
- `SPIDER_RAIN=1` fakes rain for testing. Only the approximate location is used; nothing else is sent.

### 14.4 Notification pop-ups ("Notice Pop-ups", `feelCommotion`)
- `WindowTracker.onBanner(screen)` ⇒ jump (7.5). Volume or brightness changes (`Commotion {louder, quieter, brighter, dimmer}`) ⇒ it only looks up. Volume: system volume change notifications (Windows: `IAudioEndpointVolume` callbacks). Brightness: built-in display (Windows: WMI `WmiMonitorBrightness`/ DDC). **Never read what a notification says.**

### 14.5 Dancing to music ("Dance to Music", `danceToMusic`, default on)
Two parts: hearing and moving.

**Ears** (macOS: Core Audio process tap, 14.2+, global tap excluding itself on a private aggregate device): opens **only while another app is actually playing sound** — checks once a second (`kAudioProcessPropertyIsRunningOutput`), closes 12 s after it stops. Reopens a silent tap every 10 s while apps play. First open triggers the OS permission prompt. Status: unsupported / off / quiet / listening / hearing(bpm) / deaf; the panel shows a status line. **Windows:** WASAPI loopback capture (`AUDCLNT_STREAMFLAGS_LOOPBACK`) on the default render endpoint; detect other apps playing via `IAudioSessionManager2` active sessions or the endpoint peak meter. Nothing recorded or kept — only the beat is taken.

**Beat tracker** (`BeatTracker`, `Beat.swift` ≈ 555 lines — pure DSP, port it with an FFT replacing `vDSP`): log-band spectral flux at **100 fps** → tempo by autocorrelation comb over {1,2,3,4,8 beats} with a log-normal prior centred on **118 BPM** → phase comb on full+low-band onsets → a PLL clock nudged into line, never jumping; outputs `MusicBeat{bpm, phase, confidence, energy, bar}`. Notes: simple-ratio tempo flips (3/4, 4/3, 2×) are the same pulse; the first frame after silence must not count as an onset; speech never runs >~6 s "playing" so the spider needs **3 s steady** (`musicSteady`) before it reacts; `displayLead` ≈ 35 ms to cover ~2 refreshes of screen delay (tap → air latency measured 26 ms on laptop speakers; tune per device). `SPIDER_BEAT_LAG=ms` shifts.

**Moving** (`Spider.groove`): `followBeat` (own beat eased to the music's, coasts 2.5 s through gaps), `.groove` activity: bob/stomp/pump/peacock/arms moves, changed on the bar every 8 pulses, half-time over 150 BPM; body offsets applied straight off the beat (no springs); `updateGrooveLegs` holds standing feet in the world; raised legs need `legBend`; legs between standing and raised are paced by the pulse; a dance must end even if a foot can't find ground (`grooveDoneFor`). **Cooldown (owner: "dances too much"):** one dance when music starts (`wantsToGroove`: steady 3 s, not yet `musicWelcomed`, within 40 s), then dancing is a habit in the weighted draw (`mayGrooveAgain`, `3·play·hw(danceMusic)·showW`) once `grooveRestUntil` (= `grooveCooldown` 40–90 s × laziness ÷ √weight, ≥ 3 s) passes; later dances 0.7× as long; `musicWelcomed` resets after 30 s quiet. Dial 0 ⇒ no dance even at the start. Studio ▶ fakes a 120 BPM beat. In test modes the spider mutes what it hears.

### 14.6 Lock/unlock and away
- Screen locked / session switch ⇒ the spider goes `dormant` (put to bed while you're away; whatever roused it, back to sleep); on unlock `wakeAndGreet()` (also re-checked every 0.5 s: never left asleep for good by an unheard unlock). `greetOnWaking`. Idle time (`lastUserActivity`) drives sleep, "company", "alone" memories, and wildlife gating.

### 14.7 Permissions summary
Window geometry needs no permission. Screen capture (opt-in) is used in three places: camouflage by actual pixels, measuring window corner radius, and climbing web pages (18.2). Audio capture only while music dance is on. Location (coarse, via IP) only for weather. Nothing is ever sent except the weather lookup and opt-in bug reports.

### Done when (Stage 14)
- A fullscreen video puts the spider in cinema manners within 4 polls and releases it after; a maximized front window does the same; second window in front restores normal.
- Plugging in/out the charger, Battery Saver on/off, a toast, volume change, and music each cause the documented reaction once.
- Music from any app starts one dance within a few seconds, then occasional repeats per cooldown.

---

## Stage 15 — The box, visitors, thoughts

### 15.1 Keeping it in a box
- **Behavior ▸ Keep *name* in a Box…** dims the desktop and lets you drag a rectangle (Esc cancels). Persisted (`confine`), shown as a faint dashed outline; **Redraw the Box…** / **Free *name* from the Box** alongside while set.
- Not a cage: a throw/fall/walk may take it out, but the moment it finds itself out, getting back is first on its mind (`returnToBox`): walk round its own window to the nearest stretch inside (whichever way round is open and shorter), or leap to the nearest spot inside it can reach, or leap to whatever gets it nearer and try again; out for a very long while it is fetched.
- Inside: climbs whatever windows/edges fall within the box exactly as usual, turns back at the box's edge rather than leaping off, leaps only to spots inside, prey is released inside. The map is clipped to the box (2.4). A box with **nothing to stand on**: it makes its way to it and *hangs in from the top on a line*, swaying lightly like a draught, shifting its height now and then, the odd little bounce — never a real swing (`hangOnly`).
- Boxed: decides about half as often (×2.2 slower), rests/looks far more, dashes far less (`chill 0.4`), gives up swinging on lines and hammock trips altogether.
- Freed: carries on from wherever it is and wanders off in its own time. A box drawn is set aside while the tank is open.

### 15.2 Visitors
- Opt-in (**Visitors** page: "Let Other Spiders Visit" with frequency (`visitFrequency`) and stay (`visitStay`) sliders; **Dismiss Visitors**). Enabling shows a CPU warning (no energy alert in the welcome tour; just small print).
- A visitor is a `Spider` with its own sprite window, a **random look** (`SpiderDesign.random()` with no name/packs/phrases, **no living coats** — so no camouflage, hammocks disabled), not customizable, not saved, copying the owner's leg-system setting. At most **5** at once.
- Behavior: drop by, **play with your spider** (hellos, dances, tag: `friendChase`/`friendFlee`), react to the pointer, join toy play, and **leave** by walking to a screen edge and leaping off (`leaving`, `departing`); a visitor leaves at `leaveAt` (stay). Only the owner's spider leaves traces.
- Test hook: scripted check of arrival, tag, departure.

### 15.3 Thoughts and words (Studio ▸ Thoughts)
See 6.7. Pack tick-boxes, own lines (one per line, join the same hat), **Think something now** previews, "Thinking out loud" (`muse` dial lives on this tab).

### Done when
- Draw a box; spider stays in/returns; hanging-in-from-top works with empty box; visitors arrive, play tag, leave; ≥ 5 cap enforced.

---

# PART G — THE APP

## Stage 16 — App shell: tray, panel, settings, Studio, My Spiders, welcome, entrance

### Goal
The product becomes an app a stranger can install, configure, customize and live with.

### 16.1 Lifecycle and process model
- Single-instance, no taskbar/Alt-Tab presence (menu-bar-agent equivalent): a notification-area icon is the only visible chrome. Launch at login (default off; welcome tour offers it). Windows: registry `HKCU\...\Run` or MSIX `StartupTask`.
- Start-up order: load settings → build `SurfaceMap` → build overlay windows → start tracker → create `Spider` with saved design → apply settings → start clock. **Warm up** the panel and habitat window in the background at launch so the first click/open does not stall (macOS needed a hidden pre-show of the popover 50 ms retries, up to 1 s; the first habitat open went 1440 ms → ~10–13 ms by moving surface tracing, art painting and decor panel construction off the main thread).
- **Reset Everything:** the app relaunches itself, rebuilding every window and re-reading the desktop; design, settings and hammock are kept.
- **Bring *name* to the Middle:** puts it in the air in the middle of the main screen, letting go of everything (line, hammock, pointer, meal); it falls from there onto whatever is below. (Anti-"lost spider" lifeline.)
- **Hide/Show** (`hidden` setting): toggles it off; tray icon dims while hidden. `paused`: freezes in place.
- Persist across restarts: design, settings, hammock (kind and all), box, memory, habitat, habitat knowledge, weather clock, which side of the glass it was on (`inHabitat`).

### 16.2 Tray icon and context menu
Left-click the tray icon opens the **panel** (16.3); right-click (or the menu equivalent) shows the menu:

| Item | Action |
|---|---|
| Hide *name* / Show *name* | toggle visibility |
| Spider Studio… (⌘,) | customise |
| Come Here | it walks or jumps to your pointer |
| Open Habitat / Close Habitat | the terrarium |
| Behavior ▸ | Say Hi, Toss It, Swing!, Feed ▸ (Release a Cricket…), Let Creatures Wander In, Build/Nap in/Clear the Hammock, Keep *name* in a Box…, Peek-a-boo |
| Size | Tiny 0.62 · Small 0.78 · Medium 0.95 · Large 1.2 · Chonky 1.55 |
| Energy | Sleepy 0.5 · Calm 0.8 · Normal 1.0 · Playful 1.5 · Caffeinated 2.4 (the same value as the Studio's Energy slider: `liveliness`) |
| Follow the Cursor, Pounce on the Cursor, Shoot Webs, Build Hammocks, Click to Pick Up | toggles |
| Climb Web Pages | (Your Mac) hidden for now (`pagesReady = false`) |
| Pause | |
| Launch at Login | |
| Check for Updates | looks now, offers it with release notes |
| Bring *name* to the Middle | |
| Reset Everything | |
| Quit | |

While the tank is open: an extra **Habitat** menu (Save This Habitat… / Save Changes ⌘S, Save as New… ⇧⌘S, Bring In a Habitat… ⌘O, My Habitats) and a **Weather** menu; an Edit menu so name fields accept paste.

Right-click **on the spider** (or its bubble) opens the chat directly when the talking spider is on (no menu — its items are redundant); with it off, the menu shows. Double-click stays celebrate.

### 16.3 The panel (seven pages, in this order)

A rounded popup under the tray icon: a strip of page icons, the page title small in capitals, the page's content in rounded cards. Pages are all laid out at once and the panel is as tall as the tallest (switching only swaps visibility) so there is no jump. When closed, `refresh()` is a no-op (it refreshes as it opens) — refreshing 48 times while hidden cost ~38 ms each. Rows: `toggle(title, help)`, `slider(title, low, high)`, `choice(options)`, `buttons([...])`, `note`, `status`.

1. **Spider** (house): [update button when found] · Hide/Show · Spider Studio · Come Here · **Pause** · *Size* (5 choices) · *Energy* (5 choices) · *Growing Up*: **Learn From Experience** (+ one-line summary of how it's been shaped; **Forget It All**).
2. **Feed** (fork.knife): *Let Something Loose* — eight buttons (Cricket, Worm, Fruit Fly, Moth, Beetle, Ant, Mosquito, Ladybug). *Wildlife* — **Let Creatures Wander In**, slider **How Often They Come** (Rarely…Now and Then; label shows "About one every N minutes", N = `5400·(600/5400)^freq / 60`), **Creatures Live in the Habitat**. *Appetite* — status "*name* is stuffed / content / could eat" (fed > 0.66 / > 0.2 / else).
3. **Behavior** (sliders): *The Pointer* — **Watch the Cursor**, **Come to the Cursor**, **Pounce on the Cursor**, **Click to Pick Up**. *The Desktop* — Stand on Widgets (mac only). *Silk* — **Shoot Webs**, **Build Hammocks**, Build/Clear hammock buttons. *Traces* — **Leave Traces**, slider **Most at Once** (A Few…Unlimited), **Tidy Up**.
4. **Play** (sparkles): *Ask It To* — Say Hi, Toss It, Swing!, Peek-a-boo, Come Here, Keep in a Box… *Toys* — Laser Pointer, Ball, Feather, Bell, Wind-up Bug, **Put Away**, **Bell Sound**. *Places* — **Open Habitat**.
5. **Your Mac** (laptopcomputer): **Low Power Mode**, **Feel the Battery**, **Notice the Weather**, **Notice Pop-ups**, **Dance to Music** (+status line), **Rain on the Screen**; *Web Pages* — Climb Web Pages (+ Add to browser…) (hidden).
6. **App** (gear): **Launch at Login**; *Updates* — Check Automatically (daily), Install Automatically (on quit), Check Now; *Start Over* — Reset Everything; *Help* — Replay Welcome Tour, Send a bug report / Show Me Round the Habitat; *Support* — free app note + link.
7. **Visitors** (person.2): **Let Other Spiders Visit**; *Visits* — How Often (Rarely…Often), How Long They Stay (Briefly…Ages), Dismiss Visitors; *A Note on Power*.

An update the daily check finds waits as an **Update to …** button at the top of page 1 rather than popping up.

### 16.4 Settings keys
Appendix B. Highlights: `scale, interactive, paused, hidden, followCursor, approachCursor, pounceOnCursor, webs, hammock/hammocks, traces, traceLimit, widgets, wildlife, wildFrequency, tankWildlife, visitors, visitFrequency, visitStay, learns, feelPower, feelWeather, feelCommotion, danceToMusic, showRain, toySounds, lowPowerOverride, climbPages, confine, inHabitat, welcomed, askedToSeePages`.

### 16.5 Spider Studio ("Mii-maker")
A normal window (furniture to the tracker). Left: a little **terrarium preview with your spider living in it** — it walks the walls, leaps to the ledge, and you can click, drag and throw it; the preview is a live `Spider` that follows the toggles. Right: tabs. **Every change shows up in the preview and on the desktop immediately — nothing is "applied".** Edits don't touch a saved spider until you Save.

**12 tabs, in order (index 0…11):** Body · Face · Hats · Extras · Legs · Colours · Markings · Personality · Gait · Habits · Thoughts · My Spiders.
- **Body:** 11 shapes + custom, 3 fuzz levels, size. **Face:** eye styles (13+custom), brows (10), mouths (11), face-over-legs checkbox. **Hats:** 38. **Extras:** 30. **Legs:** 13 styles + custom (changes the rig). **Colours:** 30 flat, 16 gradient, 15 living, custom (body+leg colour; blend 2–3 colours any direction; shimmer); *Camouflage* offers a Screen Recording-style permission button (on Windows: just a toggle to use real pixels). **Markings:** 20 + 20 accent colours or custom, `camoMarkings`.
- **Personality:** temperament preset (8) or six sliders (energy, curiosity, bravery, playfulness, affection, laziness).
- **Gait:** walking style (steady/mixed/bouncy/tiptoe/lumbering/scurrying), pace, stride, bounce, stance, bounciness, **Leg motion** (Classic / Natural / Refined; optional New leg system checkbox), dials preserved through Randomize.
- **Habits:** the ~30 dials of 6.4 with ▶ demo buttons (grouped Getting about / Antics / Quiet moments / With you). Dial: all the way down never, middle as usual, all the way up every chance.
- **Thoughts:** at top an **Apple-Intelligence-style on/off switch** (`intelligence`; separate from `voice` pictures/phrases which it falls back to), pack tick-boxes (Chit-chat, Encouragement, Spider facts, Bible verses), custom lines, "Thinking out loud", **Think something now**, and (when on) a "how it talks" field (`manner`).
- **My Spiders (tab 11):** cards of saved designs (click = bring out; right-click = Bring Out / Make a Copy / Delete…); **Save as a New Spider**.
- Header: name field (rest the pointer on the spider and a name tag appears); the **dice** picks a name; **Surprise Me** rolls a whole new spider; **Start Over**. Under the name: "✓ Saved in My Spiders" / "Changed since you saved it" + **Save (⌘S)** + **Revert**.

**Saved spiders (My Spiders).** One JSON per `SavedSpider` in `…/Spiders` (override `SPIDER_LIBRARY`). `currentID` (key `spiderCurrentSave`) says which saved one is out. Seeded with the existing spider the first time, keyed on the folder not existing. `matches()` ignores `gait.motion` (an animation choice kept across switches). Surprise Me / Start Over **clear `currentID`** (a new spider, so Save cannot overwrite the old). **Ask Save / Don't Save / Cancel before Surprise/Start Over/bringing another out only if the spider out isn't saved anywhere and isn't an untouched throwaway.** Still one spider out at a time; memories are shared by every saved spider. No panel switcher (not done).

**Design save format:** JSON, tolerant decode (6/1.5). Randomize keeps leg motion and the new-leg toggle.

### 16.6 Welcome tour (first run; replayable from App page)
Pages: hello → "**It'll live in your menu bar.**" (a *live picture of the real panel*, page 0, generic: `panelPages(generic: true)` and a nameless design) → "**But first, a few house rules.**" (six switches: wandering bugs, visiting spiders, traces, learning, weather, open at login; small footnote that all can change later; turning visitors on shows soft small print under the switch, no energy alert) → the Studio. **Rules:** generic — never the user's own spider name or memory summary; headings must read as one story. Windows copy: "notification area" instead of "menu bar".

### 16.7 First entrance
`Spider.makeEntrance`: `Entrance` stages **stir, peek, look, shy, drop, hello, then a swing off**, plus a tray-icon wiggle (`wiggleIcon()`). It comes down on a line from the tray icon/top of the screen. On macOS 26 the menu bar is see-through so the spider's pose is clipped above the bar's bottom by adding a strip to `pose.hiddenBy` and the drawn silk is trimmed to start at the bar; the anchor starts above the screen so the off-screen-anchor cut is skipped; `webFromDepth = Int.min` so a window behind the bar does not count as "came over the line". (On Windows, drop it from the top of the screen or from the tray area; no clipping strip needed.)

### 16.8 Bug reports (opt-in)
`BugReport.swift` (≈ 970 lines): in-app form, optional screenshot, sends to a **Cloudflare Worker** (`tools/report-worker`) that holds the Discord webhook secret and relays. The Worker URL is baked in at build time (`REPORT_URL`) and is not secret. Platform-neutral — port the form and POST; the Worker is unchanged.

### 16.9 Acceptance for Stage 16
- Fresh install shows the tour, creates a default spider, runs the entrance, persists everything through quit/relaunch (design, size, hammock, box, memory).
- Every panel control reads and writes its setting and takes effect live; the panel's first open is < 100 ms.
- Studio: all 12 tabs functional; Save/Revert/My Spiders flows incl. the ask-before-losing dialog; Surprise Me clears the current save.


---

# PART H — THE HABITAT

## Stage 17 — The habitat (terrarium)

**What it is.** A glass tank in a dark frame, in its own resizable window, containing a painted living scene, furniture it can climb, weather, creatures and ecology. It is the same spider with the same behaviors, moved onto a *second surface map* (the tank's) — plus a great deal of tank-only intelligence. It is ≈ 35% of the macOS codebase (HabitatScene, Window, Weather, Art, Geometry, Nav, Ecology, Objects, Structures, Nature, Curiosity, Places …). **Build it in the sub-stages below, in order; each is checkable on its own.**

**Owner direction (phased plan).** Geometry foundation → structures (man-made, Terraria-like) → nature library → curiosity (semantic understanding) → places (functional intelligence) → ecology (objects + prey + weather as one ecosystem). After each phase the owner said STOP; later phases were not to be started unasked. Keep that layering: each phase's code is **gated** so that with the next phase's inputs absent nothing changes (the desktop and earlier phases stay byte-identical).

### 17a — The world, spaces and camera

**World.** The tank is a persistent 2-D world, bigger than its window, **strictly 1:1 with the desktop** (never shrink the spider or zoom the normal view). Size from the display: `width = clamp(round(screenW × 2.75), 3000, 5600)`, `height = clamp(round(screenH × 1.35), 1050, 1600)`, worked out the first time from the main display's visible frame (default 1470×920 → ≈ 4042×1242) and **saved with the habitat** (a habitat saved in a world of another size is placed in the middle of the new one; moving displays changes how much the window shows, not where things are). `Habitat.world` nil = legacy 900×540; `movedIntoWorld` upgrades an unmodified old preset (`sameLayout` within 6 units) or centres a custom one.

**Four coordinate spaces** (documented at the top of `HabitatCamera.swift`): *screen · window · view (the glass) · world*. Inside the tank the spider, prey, furniture and the `SurfaceMap` live in **world** points; the only conversions are in `HabitatSceneView`: `worldPoint(fromScreen:)`, `worldToScreen`, `visibleWorld`, `glassOnScreen`, `groundLipOnScreen`. Crossing the glass calls `Spider.shiftSpace(by:)` (moves every stored absolute position) then `moveInMidAir`/`hopIntoHabitat`/`dropOutOfHabitat`. Held in the tank, the overlay draws `pose.shifted(by: worldToScreen)`; the desktop overlay's drag converts via `SpiderView.toSpider`.

**Camera.** "The glass follows the spider about, quietly": a dead-zone — it can wander over the middle of the window without anything moving; only when it strays toward an edge does the view ease over after it and settle, with a little more room ahead than behind. Critically-damped spring `ω = 2.5`, `k = ω²`, `c = 2ω`, max speed 1600; `returnAfter = 90 s` (left looking elsewhere for a minute and a half, the view drifts back by itself). User control: drag the bare glass (flick coasts), two-finger sideways swipe (or shift+wheel), arrow keys; the spider carries on regardless. **Find …** button at the edge of the glass points to the spider when it is out of sight and takes you there. The camera position is saved (`habitatCamera`), as is the glass's size/position (`habitatGlass`). While decorating, the glass does **not** follow the spider; dragging a thing to the glass edge takes the view along.

**Scene layers (a retained scene graph — rebuild with your own):** `backdrop` (sky/scenery/air back+mid/weather back+mid; parallax 0.5; sized for the largest screen so resizing never repaints) · `content` (world: ground, items, creatures, air-front, weather ground/caps/fall, tank end walls; moved by `bounds.origin`) · glass-level (weather shade/front/flash, glass). **Culling:** item layers hidden off-glass; unpainted beyond 2.5 views; prey/spider not drawn off-glass; air-front zones per 900-unit strip; emitters follow the glass. Heavy weather pictures (cloud decks, night sky, fog, rain sheets, snow caps) **paint lazily** (`paintLater`). Everything is drawn *in* the tank, among furniture, so foliage in front hides the spider as it walks behind, and other windows cover it like any window.

**Overview ("Map").** The whole tank at once, small — a map not a view into it — showing where the window is looking (drag the frame to look round), where the spider is, anything loose. Click anywhere and the glass goes there life-size. The only reduced-scale view. While decorating, the Map lets you pick anything up and put it anywhere.

**Entering and leaving.**
- **Open Habitat:** the tank rises into place over the spider; the spider shoots a line up to the lip of the tank's ground, climbs it hand over hand, and hops over onto the ground inside. (Up on a window or wall it drops first; off to one side it walks over; in its hammock it gets up; thrown over the tank it just drops in.)
- **Let Out / the close button:** the spider drops from exactly where it was (off the log/branch/glass) onto whatever is below on the desktop as the tank fades; if it's somewhere the window isn't showing the view goes to it first. Opened again with it inside, it is back where it was, and so is the view. The side of the glass it was on is remembered across restarts.
- Picked up in the tank it is in your hand, drawn over everything; carried out through the glass and let go it is on the desktop and after a while climbs back in the same way. Carried over the tank and let go, it is in. Click the glass and it rings. Drag the tank and it comes along.
- While the tank is open, desktop-only things wait outside: hammock, box (a drawn box is set aside), cinema manners, laser, visitors, traces. Toys/laser/hammock/visitors stay on the desktop.

### 17b — Biomes, scenery and the painted tank

`Biome`: forest, jungle, desert, meadow, cave, beach, tundra ("Snowfall"), night ("Moonlit"). Eight scenery tiles in Decorate ▸ Scenery. The furniture takes on the light of the place — bluer by moonlight, dimmer in the cave.

**Presets** (`Habitat.Preset`): Forest Floor, Jungle Canopy, Desert Scrub, Wildflower Meadow, Cave, Beach, Tundra (Snowfall), Moonlit, Empty. Each ready-made tank is laid out **end to end**: its old (legacy 900×540) arrangement in the middle, and either side of it **parts** with a character of their own (`LayoutBuilder` regions; `HabitatRegion.Kind`): a thicket, a clearing, a pool, rocks, a hollow log and bark to shelter in, a trunk with branches going up into the air of the tank and vines down from the lid. **Surprise Me** lays a new one out the same way, part by part (`surprise(world:)`). `Habitat.regions` infers regions for place memory.

**Painting** (`HabitatArt`, `HabitatItems`, `HabitatNatureArt`, `HabitatHomeArt`, `HabitatPieceArt`; ≈ 5.7k lines): palettes, sky, scenery (repeated across the wide frame by `panels`/`mid()`/`count()` so thumbnails stay pixel-identical), substrate you can see through the front, glass, and every item's picture. `HabitatArt.Frame(world:)` (u = 1, scenery air 466, sky above). **Rule: art must call the same `HabitatShape` paths the geometry uses** so painting and physics cannot drift. Use native BGRA premultiplied for layer images; keep big images few (the OS compositor keeps its own copy of every layer image — footprint 246 vs 220 MB). Tank art is painted off-main on a `HabitatPainter` with a per-layer generation and `still:` guards.

**Atmosphere** (`HabitatAtmosphere`, ≈ 600 lines): what moves in the air, per biome, as animated layers and particle emitters — clouds drift, light shafts breathe, leaves fall, mist rolls, butterflies wander, the sea rolls and sparkles with gulls and a sailboat, sand blows and a tumbleweed goes by, crystals glow and water drips in the cave, snow falls under the northern lights, stars twinkle, fireflies blink by moonlight; plants sway, crystals/mushrooms glow, water dishes ripple. It all stops while the tank is hidden (`setAnimating`). **Windows implementation note:** there is no `CAEmitterLayer`; write a small GPU/CPU particle system with these constraints from the macOS traps: fast short-lived particles born above the view must still reach the view (use scrolling sheet layers/keyframed layers for rain, hail, distant rain, meteors; emitters only for slow, side-blown, or born-in-view particles); every property set in an animated transaction is an animation, so update only what changed and go idle after ~1 s of clear skies; blend modes can be ignored in the macOS window server path — design with plain alpha tints.

### 17c — Furniture: definitions, geometry and the tracer

**Item kinds.** `HabitatItemKind` has **≈ 250 kinds** in these groups (labels are user-visible; names are saved as strings):
- *Perches (12):* log, branch, driftwood, corkBark, hide, rock, boulder, bamboo, cactus, plant, vine, waterDish. *Plants & details (10):* fern, grass, flower, succulent, mushrooms, moss, leafPile, pebbles, twigs, crystal.
- *Structures:* thinBranch, mediumBranch, thickBranch, shortBranch, longBranch, forkedBranch, yBranch, crookedBranch, twig, root, climbingRoot, driftwoodArch, driftwoodSnag, bambooPole, bambooSegment, driedStem; *bark & platforms:* corkSlab, corkTube, barkLedge, slateLedge; *vines:* thickVine, thinVine.
- *Supports (hardware):* brace, branchBracket, wallAnchor, glassMount, suctionCup, verticalSupport, horizontalSupport, crossBrace, hangingHook, vineClip, shelfBracket, wallRail, metalStrut, angleBracket, stake.
- *Built (workshop):* beam, post, plank, plywood, dowel, ladder, pipe, brick, woodBlock, crate, rope, backPanel, pegboard. *Building (a house):* floorboards, wall, door, doorClosed, window, windowOpen, gableRoof, stairs, kneeBrace, fence. *Backing walls:* woodBacking, brickBacking, stoneBacking, logBacking, wallpaper, backWindow.
- *Home:* bed, table, chair, bookshelf, sofa, fireplace, floorLamp, hangingLamp, lantern, candle, stringLights, rug, picture, clock, houseplant, spool, teacup, flowerBox, sign, armchair, desk, dresser, wardrobe, bunkBed, piano, stove, fridge, counter, bathtub, chest, coatRack, beanbag. *Decor:* tv, radio, laptop, recordPlayer, globe, vase, bookStack, flyJar, trophy, painting, poster, mirror, curtains, dartboard, wallShelf, sconce, chandelier.
- *Nature library (Phase 3):* structures (twistedBranch, threeFork, exposedRoot, rootTangle, stump, driftwoodRoot, driftwoodBranch, corkTunnel, leaningBark, bambooTipi, hangingBranch, lianaLoop, hangingRoots, stickRaft, mossPlatform, rockSpire, stoneArch); *shelters (covered places it can really get into):* barkCave, rockCrevice, logDen, curledLeafHide, leafCanopy, rootHollow, mossyHide, hangingLeafShelter, overhang; *plants:* smallFern, largeFern, broadLeaf, trailingPlant, climbingVine, grassClump, floweringPlant, tinyFlowers, aloe, jadePlant, lithops, airPlant, miniPalm, deadPlant, fiddleheads, creepingCover, hangingFoliage, mossCushion; *ground:* gravel, sandDrift, pineNeedles; *natural details:* mushroom, mushroomCluster, tinyMushrooms, glowMushrooms, shelfFungus, lichen, acorn, seedPod, pineCone, seaShell, snailShell, fallenLeaf, curledLeaf, deadLeaf, leafHeap, pebblePile, smoothStones, crystalCluster, petals, puddle, shedBark, twigPile; *functional (things for something):* rockPool, feedingPlatform, baskingStone, lookout, silkFrame, climbingBark, moistMoss, shelterCanopy; *loose (light enough to be blown or nudged):* looseLeaf, petal, tinyTwig, feather, seed, smallShell, tinyPebble.
- Each kind has a `HabitatObjectDefinition` (made once): label, category (perch/scenery), size, **placement** (ground / rests / wedged / hangs), sway, windLean, shadow, `shape`, `group` (sub-heading), `traits: HabitatTraits` = material, `suits: Set<Biome>`, `niche` (on materials / side / damp), `functions` (water, feeding, basking, lookout, silk, climbing, humid, cover, retreat), `loose: LooseBody?` (motion/mass/drag/windCatch — **physics not implemented**), plus layer (.rear for `rearItems`), mount (.wall), stretch (.vertical/.horizontal/.both), snow (`.bare`), note, ports. Anchor kinds refuge/drink/bask/lookout/feed. **Add-tab shelves:** structures, supports, shelter, plants, ground, details, functional, loose, built, building, walls ("Backing"), home, decor.

**Items.** `HabitatItem { kind, position, size, flip, order (in front/behind), uid (UUID — custom decoder; `giveIdentities()` on load migrates old saves; duplicate/put old give new ones), id: Int (in-habitat key for layers and map owners), … }`. `Habitat { biome, items, nextID, world, links, regions, … }`.

**Geometry (`HabitatGeometry.swift`, Phase 1).** `HabitatShape` holds the paths the painters AND the geometry use (logBody, branchLimb, driftwood, barkSlab, rockPath, bamboo, cactus, plant*, vine*, dish). Parts are:
- `.bulk` — unions with whatever touches it, including the ground;
- `.limb` — its own loop; meets others at `SurfaceJunction`s.
Geometry is clipped to the painted image (`HabitatShape.pad`) — plant leaves overflow and get chopped in the art.

**`SurfaceTrace`** (turns all the shapes into walkable loops; the hardest part of the model — read the Swift, 1445 lines):
- grow outlines by the standoff; split at crossings; drop swallowed pieces (inside test = winding of the other's grown path, plus `distance < g − 3%` for self-folds; arc step ≤ 0.4 rad or caps get trimmed); follow/union-switch; `mended` (joins a run end to a start < 2 units away even if the end vertex is shared, but only when both ends are on bulk/rim — broken floors in 360 random stress tanks 13 → 1); `tieLooseEnds`; holes smaller than π(2g)² dropped; edges attach to loops by *part*, not owner (by owner, a plant's foliage loop got the whole rim incl. the lid → spider always "sheltered").
- The main rim = the largest rim chain (`"screen:0"`); rooms `"screen:0~r"`. `SurfaceLoop.owners` names the thing each seg belongs to (0 = the tank).
- **Shelter rule:** a covered room must connect to the floor — a space shut all round is a separate, unreachable loop. Bulk shells open on one side (ground runs in through the mouth); arches/tunnels whose legs are limbs sunk into the soil (the floor runs under them). Mouth and inside must clear 2×standoff (34 at scale 0.78). Refuge anchors sit ≥ standoff from inner walls.
- **Shape traps:** concave dips tighter than the standoff fold when grown (bumps via |sin|, toothed pine-cone outlines, tight spiral coils) — paint the detail, keep outlines smooth. A ring of limbs (hanging-perch bridle, closed frame panes) seals its inside — leave a gap. Low limbs (< 2g) are walked through — make them bulk.
- **Junction crossing** (`crossJunction` in `advanceAlong`): keeps `walkDir` (belly stays to surface); forced at a run's end; 30% optional otherwise; never when purposeful/rolling.
- Swaying climbables are held still (`ItemLayer.setHeld`) while the spider is on or within 60 units — in a gale a long vine's picture leans 150+ units off its geometry.
- Dev overlay ⌃⌥⌘G / `SPIDER_HABITAT_GEOMETRY=1` draws parts, junctions, interaction points.
- Tool baseline: feet on nothing painted 19.5% → 0.6%.

### 17d — Structures and building (Phase 2)

Owner direction: man-made materials ("2×4 beams… like something they made the spider"); **brackets must not float** — suction to the glass unless over a wooden backing wall (screwed); a lone bracket is never the only support; **Terraria-like building** (backing walls behind rooms, solid walls, doors/windows, rooms the spider walks in); lots of interior decor (fun and expressive over realism); **the spider opens doors itself**; doors thinner than the wall, smooth swing, no slit of air beside a doorway.

- **Pieces:** each kind lays out as sticks/blocks/bars/visual/ports (`HabitatShape.piece`; `leaf()`, `opening()`). Multi-block pieces: each block grown by `k·0.06` so no collinear edges (the tracer can't resolve them). Bulk posts + beam seal rooms → slender built pieces are limb "bars".
- **Supports** (`supports()`, `isBacked`, `footing`, `addSupport`, `supportFloating`): props from below (natural → forked `.stake` standing on whatever solid is under it; built → `.verticalSupport` back post); backing wall behind ⇒ bracket **screwed in**; else **suction bracket** (art draws suction cups vs screws via `ItemLayer.backed`). Leaning on hanging things/vines/string lights holds nothing up. Presets call `supportFloating` (stakes).
- **Links:** saved by uid+port; along-child on a point parent slides (`over`, point straight above); flat tops (cradle with half-width) let a roof/plank sit on two walls a few units off. `snap`, `realign`, `dependents/release`; ports `fits/meet/seat/over`.
- **Doors/windows:** `door/doorClosed`, `window/windowOpen` kinds swapped (double-click, inspector Open/Shut). The leaf is its own layer in `ItemLayer` (`updateLeaf`, 3-D rotation about the hinge, face/edge opacity); the main image paints the doorway lining (no air slit). **`DoorKeeper`** opens a shut door a step ahead of the spider walking at it (or pushed), summons it through, shuts it 2.5 s after it leaves; not an edit; shut again when decorating starts.
- **Leaps** (`Spider.ballistic` in the tank): nil when the arc passes > 6 units through any solid outline (`leapBlocked`) — otherwise it jumped out of sealed rooms and got stuck retrying.
- **Placement rules in the editor:** rocks, pots and the like stay on the ground; branches, logs and small things can be propped up off it; vines hang from the lid.
- **Shelf `rear`** layer items (backing walls etc.) draw behind; in-front/behind inspector toggle for plants and details; perches are always behind (it climbs them).

### 17e — Nature library (Phase 3)

Layouts `HabitatShape.nature(kind, r, s, u) → PieceBuild?` using `NatureKit` helpers (blade/leaf with midrib into `PieceBuild.ribs`, shell, mound, chaikin, raft…); art in `paintNature` (paintCork/paintStone/paintBlade/paintMoss…). Semantic definitions for later AI (17f), a searchable Add page, richer region layouts. `HabitatItemKind.definitions` cached. Checks: reach, jitter robustness, shelters at scales 0.78/1.1, presets' refuges, supports/snaps, save/load of all kinds, spider on each. ~220 Add tiles with stack+constraints cost ~30 MB heap → tiles lay out by hand + layer-drawn background.

### 17f — Curiosity: semantic understanding (Phase 4)

User said STOP after: semantic understanding / familiarity / investigation — no drinking/shelter/place-memory/ecology yet.
- **Qualities by rule** (`HabitatQuality`, 27 cases; `HabitatQualities` graded 0…1; `kind.nature` by `NatureRules` from the definition + sample shape; hand-given facts only via `HabitatTraits.extra`: lamps glow, fire warm, beds). `Habitat.qualities(of:)` adds situation (elevated/covered/exposed/hanging).
- **Interaction points** (`InteractionPoint`): inspect/touch/top/perch/underside/beneath/side/edge/entrance/interior/launch/silkAnchor/drinkEdge/waterSurface/bask/lookout/feed — part-named with a `stand` anchor. `HabitatChange` diff by uid.
- **Knowledge** (`HabitatKnowledge`, per spider): `Acquaintance` stage/exposure/unease by uid, kind familiarity, `noticeRate`, key `habitatKnowledge` (seeded "familiar" on first tank). Saved at quit and ~every 60 s (not while `testingHabitat`).
- **Things in the tank** (Spider MARK): `tankRebuilt`, `thingsCarried`, `thingsPutDown`, `senseTank`; **inquiry stages** orient → watch → approach → retreat → probe → linger; **probes** feel/peer/water/beneath/inside/otherSide/partway/top/leapOn; `headFor` routing (`firstHops`, `arrival`, `routeHop` forced in `crossJunction`, `walkGoal` stop); new activity `.feel` (front legs to `feelAt`). Dragging a thing: `thingsCarried([id: offset])`, the spider **rides** it (`rideShift`).
- **Decorating reactions**: it notices changes, explores the rearranged tank (`exploring`, weight 24).
- Traps: a flat segment's bounding rect has zero height and `intersects` nothing (pad boxes); de-dupe by point alone merged touch spots either side of a thin stem; after crossing a junction `walkDir` is kept, so a hop can lead the long way round the closed rim — count distance on the next loop too; "facing" at a stand spot must point at the thing's middle, not its nearest bit; `teleportQuietly` only nudges the body.

### 17g — Navigation (A* in the tank)

Gated on `inHabitat && !map.loops.isEmpty` (**not** on `hasJunctions` — a tank where nothing touches silently fell back to greedy hunting). `TankNav` (`HabitatNav.swift`, 1223 lines):
- **Graph:** spots every ~30 units round each loop, plus every junction vertex, open-run end and door side. States = spot × direction along the loop. Edges: **walk**, **turn** (cost 55), **hop** (junction), **leap** (validated by *flying* it with `Flight` mirroring `updateAirborne`+`leapBlocked`, +3 conservative margin, must land within ~47 units of the aim), **door**.
- **Crossing trap:** `crossJunction` only fires walking *into* a vertex. A hop edge therefore starts at the spot *before* the vertex (cost includes that walk), and plan starts add "cross just ahead/behind" entries. Getting this wrong made the spider pace at a junction until the watchdog fired.
- `noStop` states within 16 of an open-run end that has junctions (it is forced over; it can't stop/turn/leap there). Goals: spots on the goal's loop; only if none can stop there, spots on other loops within `min(within,16)+4`.
- **Following:** A* replans at every decision (0.14–0.37 ms median, ≤ 1.4 ms); legs = walk (with `routeHop` chain, continued in `replanAfterHop` while `navLive`), leap, door. Penalties per trip: called-off leap 600 then ∞, landed elsewhere +300, door that didn't open ∞, hop missed at a ledge end +400; **watchdog** 14 s without 20 cost of progress ⇒ penalise next edge, 3 strikes ⇒ `noWay`. Hunt walks aren't chopped each second while `navLive` unless the prey moved/closed (`huntMoved`).
- **Reach:** Tarjan parts ⇒ `reachable(from:dir:)` closure (compute once, ask many: `gettable()` in `choose()`); `quarry()`/`choose()`/`goEmerge` filter by it; **prey with no way to it for 45 s ⇒ `Prey.slipAway()`** (den=nil, fades where it is). `huntInTank`: same loop within 220·scale ⇒ walk along and pounce (a pounce *into* the surface is how it bites something on its own ledge: `pushOff` hop, pinned on landing).
- Built **off the main thread** in `rebuildMap` right after `applyMap` (`waysComing` → `waysWorkedOut`); sync maps (test hooks, restore at launch) ⇒ `workOutWays` on `SurfaceMap.habitatCopy` (`generation`). 140–470 ms per preset on an M2 Pro. App sets `Spider.waysOffMain = true`.
- Reference results (16 seeds × 8 presets): hunts 84 → 128/128, worst turn-backs 87 → 5, worst stall 150 s → 28 s.

### 17h — Places and errands (Phase 5)

User said STOP after: no meters or chores. Rules: **user-built shelter first** (rule 12); "the behaviors listed are not exhaustive … be creative" (added dew, warming up, mirror display, rounds, glass, ambush, meal sites, check-the-water).
- `PlaceQuality` (19 graded), `HabitatPlace` (key `uid:kind:cell` on things, `tank:x.y:facing` on the rim), `PlaceSurvey` (all places sized up once per layout, ~30 ms for a 4000-unit tank: roofs from real *edges* bucketed by column, walls by row, DDA sight lines only for high standing places), `sensed()` adds familiarity/novelty/disturbance/safety/prey, `appeal()` weighs per `PlaceUse`. `kind.waterArea`.
- **Place memory:** `HabitatKnowledge.places: [key: PlaceRecord]`, `routes`, thing `fond/lastVisit`, `clock`. Favourites pull it back (merit-scaled; far favourites never win on distance — pull explicitly; a favourite worse in itself than what is near shouldn't win).
- **Errands** (`travel` + `act` step machine; `startTankGoal` gives urges + context; `choose`: favourite pull, 4th-power weighted pick, curiosity-random): drink, shelter, hide, lookout, sleep, rest, bask, warm up, dew, ambush, forage, emerge, shade, meal sites, rounds… Invisible urges, no meters. New activity `.drink` (posture/legs/chew/ripples), dew drops (`Drop.sip`), ring `spread`. `summon(to:door:)`. `takeIn` ends yielding errands when something is added within 300 units.
- Refuse routes > `max(4×straight, straight + 1200·sc)` — but not real 3× routes (into a house); eco-only `headDist > straight + 1800·sc`. A lone leg "stub" (open loop < 2·standoff) as shelter sent a Lazy spider round the whole rim under the lid — fixed by the route refusal, not by dropping stubs from the survey.
- Traps: a cave mouth is not cover; body lines run past edge ends (use `loop.edge` for roofs); hanging at an underside's very end slips round the corner — only count continuous undersides; an eye target straight below turns it face-on (drop `eyeOn` while drinking); `headFor` calls `lookAhead(dir)` — an `eyeOn` look target behind the spider (the glass it had been peering at) holds `interest` like the pointer and made a 14 s errand walk go the wrong way.

### 17i — Ecology and creatures (Phase 6)

User rules: prey arrivals are **odds**, never deterministic spawns; no survival meters or chores; personality via existing traits; STOP after ecology/weather/prey integration is robust. `HabitatEcology.swift` (eco-gated; with `eco == nil` the desktop is identical):
- `SkyCover`: roof-like parts only — bulk parts, cover/retreat things, broad leaves (w > 0.8h); a branch or vine over the floor is **no roof** in a side-on tank; leafy cover counts 0.4 with soft edges. Rain wets, snow lies, only where the sky is open: the floor under a table, a roof, a stone ledge, a cave stays dry and bare; broad leaves only thin it. Rain beads on leaves and stays after (drying faster in sun and wind); fog leaves a dew; rain rings the water in a dish/pool out under the sky; gale ⇒ plants and hangings lean and flutter (open ones far more); stone warms in the sun and stays warm a while.
- `EcoFeature` pull table → PreyKind weights (glow only at night); `EcoSpot` (12-unit grid, `open`/`deep`), `Droplet`, `Remains`, `Haunt`; `arrivalOdds`/`arrivalGap`/`arrival(near:)` with sites weighted `w/(1 + (d/750)²)`; `hidingPlaces`, `concealment`, `preyPull`, `light`, `water`.
- **What comes, and where** (setting `tankWildlife`, default on; Feed ▸ Creatures Find Their Own Way In): flies to flowers/fungus/food; mosquitoes to water; beetles/worms/ants to leaf litter; beetles and ants to bark and logs; ladybugs to plants; crickets to dark shelters; worms to damp and after rain; moths to a light after dark. A bare tank sees a visitor every half hour or so, a lush one every few minutes. Walkers come out from under bark or up out of litter (low and hidden); fliers come down onto what drew them. Mostly near where you're looking.
- **What they do:** fly lands on flowers; moth rests on a plant by day and circles a light after dark; mosquito hangs over water; rushed beetle makes for the bark and lies low; cricket keeps to the dark by day; worm gets into litter out of the sun; ant finds what's left of a meal (the spider leaves the husk in the tank), nose round it, carries it off; anything caught out in a downpour gets in under something. Crawlers (`amble`) walk up and over stones/logs rather than turning back at the first bump. Lying low, a creature is hard to see (for you and the spider).
- **Spider side** ("The tank alive" MARK): `weatherWorry`, `ecoWeather`, `ecoWants`, errands `.emerge/.shade/.forage`, `chainNext`, drops (`goForDrop`; only drops that have a stand spot within 34·sc; a dew errand ending `.noWay` puts that thing in `noWayToDrops` for 150 s). Out in rain it feels it getting to it — sooner the harder it falls, the stormier, the shyer — goes to the shelter it knows best (anything built first), waits, stays in a while after, a look out, a look at the sky, then out. A drop of rain on a leaf catches its eye: it goes over, a curious one gives it a touch (now and then runs off the leaf), and drinks. In hot sun it basks (warm stone most of all) then finds shade. In a gale it keeps off and gets down off whatever sways. The bold/curious go up somewhere open to watch mild weather. Hunts by where things are: lies in wait where prey comes, pokes under bark and in litter to turn out whatever's lying low; full up, lets what wanders in be.
- **Hunger** (tank only; `fed` not saved — every launch starts at 0): `hunger = clamp((0.3 − fed)/0.3)`; effects — ambush gate 180 → 40 s and weight ×(1+2.5h); forage gate 150 → 60 s ×(1+1.5h); rest ×(1−0.5h); sleep want ×(1−0.7h); sleep length ×(1−0.5h); ambush wait ×(1+0.8h); notice range ×(1+0.5h); left-alone sleep needs idle ×(1+2h). Nothing goes wrong for going without.
- Tank prey: `tankLife` (den/hidden/cover/goal/sheltering, `amble`, `probed`, `letGo`, `shownAlpha`); perch weighting `-0.6·disturb` in gales.

### 17j — Weather (Stage 17j)

Fifteen kinds (`WeatherKind`): **Clear, Blazing Sun (sunny), Overcast (cloudy), Fog, Drizzle, Rain, Thunderstorm (storm), Hail, Snow, Blizzard, Gale (windy), Sandstorm, Sun Shower (sunshower), Shooting Stars (starfall), Northern Lights (aurora)**. Rain slants and snow drifts with the wind; cloud drifts over; light dims under a storm and warms in the sun; storms have lightning (far off or right down to the ground) and thunder that shakes the tank; hail bounces and lies about; snow settles on the ground and the tops of furniture with footprints in it; a rainbow often follows rain (sun shower); rolls in and clears over ~30 s, sometimes turning into something else (rain → storm, snow → blizzard).

**Model** (`Weather.swift`, 768 lines, pure): `WeatherRecipe` channels; `Biome.naturalWeather` (what suits each scenery: sandstorms and blazing sun in desert, downpours in jungle, snow and aurora in snowfall); `WeatherSettings` (key `habitatWeather`): mode **changing** (default: a spell, then clear, then another, from the scenery's kinds) / **always** (pinned to one kind) / **outside** (follows 14.3), per-biome `custom` lists (click a tile to add/remove — "Back to … Own" resets), **pace** (how often it changes) and **amount** (how much of the time there is weather). `WeatherClock` (wall-clock spells; saved under `habitatWeatherNow`; `bring/changeNow/debugForce`) — **keeps time while the tank is shut**: open it an hour later and it has moved on.

**Drawing** (`HabitatWeather.swift`, 1698 lines): `WeatherLayers` with slots back/mid (parallax backdrop), ground/caps/fall (world), shade/front/flash (glass); `follow(visible:backdrop:)` keeps emitters and masks on the glass; cloud decks `deck`/`stormDeck` are 2W wide and repeat every W with drift wrapped into 0…W — the layer must be *centred ON the drift* (`position.x = deckOff`) or a hard clear/overcast seam appears for half of every cycle. Phase 6 wet/snow/prints/puddle masks only under open sky. `WeatherArt` also makes the Weather-tab tile thumbnails. UI: toolbar **Weather** popover (`WeatherPanel`; tiles; what it's doing now; **Bring Weather** (make it rain/snow/hail… this minute) / **Something Else** / **Clear the Sky**; Always; Like Outside) and the app main-menu "Weather" via `MenuFiller`.

**The spider feels it** (`WeatherFeel`: wind signed ±(1 in a gale up to 2 in a gust), gust, rain, snow, hail, sand, fog, sun, cold, heat, rainbow, storm; defined in `Spider.swift` so tools compile without Weather.swift): rain soaks it (darker glossy coat beaded with water, drops gathering and dripping off, splashing on its back) until it shakes itself off (`shakeOff`); fog gets it dewy; snow settles on its back while it keeps still and slides off as it moves/climbs/leaps; sand gets in its fur; it shivers in the cold and huddles; the **wind** pushes it about on its feet (leans into it, goes slower against it, flattens and holds on through big gusts; on its line it is blown out sideways ~15° in a gale, free legs streaming, silk bowing; leaps drift `vel.x += windPush·0.36·dt`); when it comes down hard it runs for cover (under a branch, leaves of a plant, anything raised off the ground, the lid at a pinch) and sits it out; a playful one may dance about in a warm rain, a bold one braces (`.brace`); hail makes it flinch; a thunderclap overhead makes it jump and stare where the lightning struck (`spider.thunder(at:loud:)`); it basks in the sun (`.bask`) or finds shade when too hot; reaches for snowflakes; stops to look up at a rainbow or northern lights with a thought now and then. It dries off out on the desktop (no weather there). **Calm weather must leave the spider byte-identical.** AppDelegate sets `spider.weather` each frame (calm unless in the tank and not held). CPU ≈ 17% clear vs ≈ 23% in a storm.

### 17k — The window, toolbar, decorating, My Habitats, tours

**Window.** A normal resizable window ("any shape"; narrow ⇒ icon-only buttons under 960 wide) in a dark frame drawn with layers; the lid along the top carries the buttons. Toolbar: **left** (getting about) — **Let Out**, **Map**; **middle** — the tank's name (click to rename); **right** — **Feed**, **Weather**, **Decorate** (becomes accent **Done**), and a round **?** (shows the tour for what's on screen again; also **Habitat ▸ Show Me Round the Habitat**). Remembers size and where it was looking. Feed here also has "Creatures Find Their Own Way In".

**Decorate.** Opens a panel *beside* the tank (the tank doesn't move); three tabs in order of use:
1. **Add** — everything in 17c with a search and a menu of kinds (shelves as chips). Click one and it drops into the most open spot of what the window is showing.
2. **Scenery** — eight picture tiles (Forest, Jungle, Desert, Meadow, Cave, Beach, Snowfall, Moonlit).
3. **Habitats** — **My Habitats**: **Save This Habitat** keeps a copy; click a saved one to put it back (⌘Z undoes it; goes through `scene.replace`); the one in the tank is marked; after changes the button becomes **Save Changes** (+ **Save as New**). Each one's **⋯** renames, updates, **shares as a `.spiderhabitat` file**, shows in the file manager, or deletes; the tray button brings a shared one in. One JSON per save in `…/Habitats` (`SPIDER_HABITAT_LIBRARY` override); `currentSaveID` (key `habitatCurrentSave`); "changed" = fitted save ≠ `scene.habitat`; presets/Surprise/Empty clear it. Under them **Start Afresh**: **Surprise Me**, **Empty the Tank**, the eight ready-made tanks and a bare one.
In the tank: click a piece to select; drag to move; drag a corner handle to resize; an **inspector** (one-line hint when nothing is picked) sizes, flips, duplicates, removes, sets **In Front/Behind** of the spider (plants/details; perches always behind), Open/Shut doors. Keys: ⌫ remove, ⌘D duplicate, F flip, arrows nudge (⇧ more), ⌘Z/⇧⌘Z undo/redo, Esc deselect then leave. Undo/redo is a stack of whole-habitat states. The habitat is **saved as you go**, with its size. A habitat from before the big tank is moved into a world of its own: a ready-made layout becomes the new one of it; a custom one is kept as it was, in the middle.

**Tours** (`HabitatTour.swift`): a child borderless window over the tank, dimmed with a **spotlight hole** on real button rects, a few words by each (Return/→ next, Esc skips). First open (`habitatTourSeen`) shows the toolbar tour; first Decorate (`habitatDecorateTourSeen`) shows a decorating tour. Generic text ("your spider"). Suppressed when any `SPIDER_*` test variable is set (except `SPIDER_HABITAT_TOUR`).

**Perf rules for the tank:** open async (surfaces/survey/ecology/ways traced on `HabitatSceneView.mapQueue`); decor panel built lazily; window + menu panel prebuilt at launch; tank frame from layers; ≤ one transaction per tick. Targets: open ≈ 10–13 ms main-thread (+ ≈ 20–26 ms later stalls), tank frame 0.6–0.9 ms main.

### 17l — Test hooks and reference runs for the habitat
`SPIDER_HABITAT_CAMERA` (~3 min, `[ok]/[FAIL]`: follow end to end and up the glass, pan away and find again, resize, add and drag furniture far along, layouts and Surprise Me, prey, a throw, carried out and back, closed with the spider out of sight and reopened, weather while it moves, the overview), `SPIDER_HABITAT_INPUT`, `SPIDER_HABITAT_TEST`, `SPIDER_HABITAT_SHOT`, `SPIDER_HABITAT_BUILD` (~85 s, spider-behaviour checks are timing-sensitive, ~⅔ pass fully), `SPIDER_HABITAT_CURIOUS` (~2 min), `SPIDER_HABITAT_PLACES` (~3 min), `SPIDER_HABITAT_ECOLOGY` (~4 min, 77 checks in `tools/perch.sh ecology`), `SPIDER_HABITAT_TOUR`, `SPIDER_WEATHER[_SHOT/_KINDS/_BIOMES/_SETTLE]`. Judge A/B by **rates over many lives** (8 seeds deterministic + 2 plain), never one run: one change to the place list diverges whole lives chaotically. Known: `SPIDER_HABITAT_INPUT` "let go in the air…" and "the glass grows, any shape" are screen-size dependent.

### Done when (Stage 17)
- Each sub-stage's harness passes on the shared core with the Mac as oracle: tracer produces the same loops for the same habitat file (export loops from both and diff); nav reaches every reachable goal; ecology/weather check lists pass; a `.spiderhabitat` file saved on macOS opens identically on Windows (keep key names!).
- Open/close the tank 50 times with no leak or stall; the tank soak runs 30 minutes at ≤ 25% CPU in storm weather.

---

# PART I — OPTIONAL AND PLATFORM-SPECIFIC FEATURES

## Stage 18 — Talking spider, web-page climbing, browser extension

All three are optional for a first Windows release (web pages is *hidden* even on macOS: `AppDelegate.pagesReady = false`, "doesn't work yet").

### 18.1 The talking spider

**Behavior.** Studio ▸ Thoughts has an explicit on/off switch (`intelligence`), separate from `voice` (pictures/phrases) which is the fallback when the model isn't available. When on: its thought bubbles are written for the moment (a "spark" → a few words), and it **answers when you talk to it**: **right-click on the spider (or its bubble) opens the chat directly**; a click on the bubble also opens it; double-click stays celebrate; with it off, right-click shows the old menu. Chat UI (`ChatPanel`): a non-activating cream pill by the spider; clicking elsewhere (resign key) or Esc closes it. Bubble hit test: `SpiderRenderer.thoughtBubbleRect(pose)`. While listening it holds decisions and bubble (`Spider.listening`, `holdStillToTalk`). Replies come back with a **feeling** (happy, loving, playful, curious, agreeing, shy, sleepy, grumpy, surprised, calm) that drives its body; the feeling is worked out **in code from the words** (`SpiderVoice.feeling(of:)`) — asked for a tag, the model said [curious] every time. `WordsAnswer = said(text, feeling) | declined | failed`.

**Owner rule:** speech is **cute, simple and sensible — never philosophical or vague.**

**Interface** (platform-independent):
```
protocol SpiderWords {
  status: VoiceStatus (ready | unavailable | …)
  muse(as design, about spark, avoiding recent, done(String?))
  reply(as design, situation, to message, after conversation [(you,it)], done(WordsAnswer))
}
```
`Spider.words` is a static hook so tools/Studio compile without the implementation.

**Prompt lessons (small on-device model; they carry over to any model):**
- Muse gets **one concrete "spark"** (`Spider.spark()`), never the whole situation — given everything it waxes poetic. The spark is chosen by weights: a noticed loose bug ×5; hungry ×3 (fed < 0.25) or full ×2 (fed > 0.85); music playing ×4; storm ×4 / snow ×4 / rain ×4 / sun ×3; time of day; etc.
- Don't put hunger in the reply background: every answer turns to eating bugs.
- Personality as **speech habits** ("say um", "hmph"), restated right by each request; adjectives alone are ignored.
- Examples are **sampled from a pool each call**; a fixed set gets copied verbatim (openers like "oh, hello!").
- A fresh session per call, 20 s timeout. Verbatim lines: verses are never rewritten; 30% of the time one of the pack's verbatim lines is shown as written, 20% one of your own lines.
- `manner` (free text "dry wit, loves puns") steers its own words.

**Backends on Windows** (decision D6): Windows AI (Phi Silica; Copilot+ only), a bundled small local model, or a cloud API. Whatever is chosen, show availability honestly in the switch's status. Evaluate with a no-UI eval harness (`SPIDER_VOICE_EVAL=n` with preset/manner/packs/ask) so the user using the machine does not interfere.

### 18.2 Climbing web pages (hidden on macOS; port last)

**Idea.** A browser that fills its screen (zoomed or full-screen) leaves no desktop and no other windows to climb, so the spider climbs the *page*: tops of cards, bars, boxes and dividers, under them and up their sides. It goes by how the page *looks*, never what it says. Only when a browser window covers its screen (within ~40 units); a smaller browser window is just a window. Browsers: Safari, Chrome, Brave, Arc, Edge, Firefox, Vivaldi, Opera, Orion, Zen, DuckDuckGo and the like (by bundle id/process name).

**Pipeline (all off the main thread):** every ~1.5 s capture the browser window; compare a fingerprint straight from the bitmap bytes; only on a change read the picture with `PageReader` (`PageLedges.swift`, 626 lines — **pure pixels-in, geometry-out; port as is**):
- **A line:** a straight run where colour changes sharply and as one step (the edge of a card, bar, box; a soft shadow along it is fine; transition ≤ 3 px wide and the strongest step; gradients and bokeh rejected), or a thin line drawn across (a divider); steady along its length; "thing-side even" (the bottoms of a word's letters are not a line, nor are photo edges which come and go along their length).
- **Room:** on one side, smooth open space (flat colour, gentle gradient, a blurred photo behind frosted glass — never the strokes of text or an icon) at least as deep as the spider is tall (`need = 44×scale`), for a good stretch along it. Room ended by a parallel line (inside a text field, between two cards) is a **slot** and needs more headroom (`slot = 70×scale`). Photo backgrounds defeat "flat room", so room allows steps ≤ 5 (`flat`) and drift ≤ 28.
- A line with room above = a ledge to stand on; room below = hang from; an upright one with room beside = a wall. Corners join if rounded (both gaps ≤ 24, within 8) or inside-square (gaps ≤ trim+4). The browser's own bars are left alone: the page starts under the lowest line right across the window near the top (whose underside is a ceiling to hang from).
- **Naming:** each ledge keeps its name across re-reads (shared overlap ≥ 50%, plus a voted whole-page shift `moved`) so re-reading a page leaves a standing spider standing. Click-through to another page, a click, the title changing (a number — **never the title itself**), or a plain picture change is noticed and read at once; a ledge that has gone from under it ⇒ it catches itself on a line shot up to the ceiling (`detachAndFall(lineUp:)`).
- **Scrolling** is followed as it happens: while a page scrolls, every ledge but the one the spider is on is put aside and that one is followed — a small patch round its feet, looked at 30 times a second and SAD-matched against the last, with scroll deltas filling in between (the gain — how far the page moves per scroll point — is learned as it goes; zero over a part that stays put like Gmail's header). Out of sight ⇒ it falls. Once the page is still it's read afresh. Global scroll/mouse-up hooks drive it.
- **Film vs page:** full-screen browser showing a page is no cinema (the spider climbs); showing a film (2+ looks with > 25% changed) it is cinema.
- Costs: idle look ≈ 5 ms CPU per 1.5 s; reading 10–30 ms (Gmail photo themes slowest); main thread lays out ledges in well under a millisecond; total ≈ 1% of a core while browsing.
- Integration: `SurfaceKind.webLedge` (onWindow), `SurfaceMap.pathLoop` (2.4), `setPages`, `rebuild(pages:pageScreens:)`; `Spider.pageLedgesChanged(moved:)`, `isPageLedge`.
- Settings: `climbPages` (default now false, hidden), Your Mac ▸ Web Pages; asks for screen capture once (`askedToSeePages`) — on Windows with Windows.Graphics.Capture the yellow border may be avoidable with the border-optional capability. Test tool `pages.sh see page.png out.png [scale]` draws green (stand), blue (hang), orange/magenta (walls), red (corners).

### 18.3 The browser extension

`Extension/` (Chrome MV3; 329 lines JS): `worker.js` (service worker; WebSocket to `ws://127.0.0.1:47219–47221`), `page.js` (content script on http/https/file, `document_idle`, `all_frames:false`), `manifest.json` (name "Spider Buddy", min Chrome 116). **It runs unchanged on Windows** (Chrome, Edge, Brave, Vivaldi, Arc…). It reports, **never anything on the page**: for the page itself (id 0) and every part that scrolls on its own: `layout {view, scrollers[id, carrier, rect, offsets], fixed}` (rects in the page's own pixels from the top-left of the page area; the DPR; what carries each when another scrolls; the parts that stay put — fixed/sticky); per-rAF `scroll` offsets; and `changed` (throttled).

**App side (`PageBridge`, 240 lines):** a WebSocket **server on 127.0.0.1 only** (ports 47219–47221, `tryNextPort`), accepting **only browser extension origins** (the browser sets the origin; a page cannot pose as one). Replace `NWListener` with any loopback WebSocket server. The app says which windows it is climbing (`want`, by top-left rects); only the tab showing in each reports. Each ledge the picture found is tied to the part of the page it is on (`carriers`: fixed → −1, innermost scroller, else page 0) and moves exactly as far as that part scrolls every frame; none is put aside; a ledge that scrolls out of its part's sight is gone; a change is looked at within 0.2 s. Without the extension everything still works by pictures.

**Distribution:** `Your Mac ▸ Web Pages ▸ Add to *Browser*…` while not connected: until the extension is in the Chrome Web Store (`AppDelegate.extensionStore`), it copies the extension to Application Support, shows it in the file manager, puts the browser's extensions page on the clipboard and says the three steps (Developer mode, Load unpacked, pick the folder). Test with a throwaway browser profile `--user-data-dir=… --load-extension=…`; never quit the user's own browser.

---

# PART J — SHIPPING

## Stage 19 — Packaging, updates, bug reports

- **Installer:** signed installer (MSIX or a signed `.msi`/Inno/NSIS), per-user, no admin. Authenticode signing with an EV or Azure Trusted Signing cert to avoid SmartScreen warnings.
- **Updates:** the macOS app uses Sparkle: appcast `https://ephemerill.github.io/spider-buddy/appcast.xml` (GitHub Pages serving the repo's `gh-pages` branch, which holds only that file), EdDSA-signed `.dmg` and appcast, public key baked in (`SUPublicEDKey`). On Windows use **WinSparkle** (same appcast format, supports EdDSA) with a **separate Windows appcast** and its own key, or Velopack/MSIX auto-update. Settings: Check Automatically (daily), Install Automatically (on quit); a found update waits as a button on page 1; `SPIDER_UPDATE_TEST=1` runs the background check immediately. **The feed address must never move** (every shipped copy reads it); back up the private key (without it installed copies can never update).
- **Release script:** version file → build → package → sign → publish release + appcast (notes markdown → "What's new"; text after an `<!-- install -->` marker is for manual downloaders and stays out of the update window). Releases are tagged `v1.x`; macOS latest is v1.0.1.
- **Bug-report worker:** deploy as is (Stage 16.8).
- **Telemetry:** none.
- **Resources:** icon set, installer art, the browser extension folder (18.3) bundled for "Add to browser".

---

## Stage 20 — Test and verification harness

The macOS project's quality came from tools, not eyeballing. Build the equivalents **as you go** (each stage's "Done when" names the one it needs).

| Tool (macOS) | Purpose | Windows equivalent |
|---|---|---|
| `tools/sim.sh` | **Headless simulator**: runs the spider against a synthetic desktop for 4 simulated minutes, then scripted passes: grab/throw/rappel/window-closes-underneath/petting; swing/hammock build/nap/wipe; every temperament preset for 150 s each; checks for cinema, maximized, notched, music (12 checks), weather, habitat sections. Prints [ok]/[FAIL]. Known "flakes" at base rate (Mosquito catch is a slow-hunt flake). | Same program against `core/` with a fake desktop (Stage 2.10). Run before every merge; compare *rates* over many seeds, not single runs. |
| `tools/preview.sh` | Contact sheet of every pose/option → PNG; `--cliptest` checks `drawRadius` covers every pose | Identical, plus a cross-platform image diff against the Mac's PNGs. |
| `tools/film.sh` | Filmstrips: walk cycle, `--desk` (actual size on a mock desktop, every edge kind — "the most useful single view"), `--peekaboo`, `--hunt cricket / worm / fly`, `--jump [--under]`, `--hang`, `--swing`, `--hammock`, `--strip corner / turn / peek / <activity>`, `--seq a:2,b,c:1.6` (hand-off frames), `--dance` | Port; these are the judge for animation changes |
| `tools/jerk.sh` | **Jerk detector:** runs the spider headless, flags every frame where body, heading, or a foot (relative to body) moves further than a frame's worth; groups by activity pair; >2 flags a minute is worth a look | Port — it catches foot teleports |
| `tools/legs.sh` | Leg quality check: stretch, reach, slip, pops, knees-through-walls, over many "worlds"; **`ab` = seeded frame-exact A/B vs a baseline copy** reporting flat tops "identical" at all 5 sizes | Port and gate every leg change on it (rule 2) |
| `tools/walk.sh`, `tools/smooth.sh`, `tools/bench.sh`, `tools/gallery.sh` | Walk filmstrips/trace, smoothness, per-frame timing, studio thumbnails | Port |
| `tools/beat.sh`, `tools/ears.sh` | Beat tracker on synth/loops/mixes/files; tap status & latency | Port with Windows audio |
| `tools/perch.sh` | **Habitat harness**: `sheet, world, air, ab, stress, loops, near, chains, rain, persist, pieces, build, nature, curious, places, ecology, nav` | Port with the habitat model (Stage 17) |
| `tools/pages.sh` | What a picture of a web page would be climbed as | Port with PageLedges (18.2) |
| App test hooks (`SPIDER_*` env vars) | In-process scripted tests of the real app: `SPIDER_STUDIO_SHOT`, `SPIDER_TRACE_TEST`, `SPIDER_TOY_TEST`, `SPIDER_VISITORS_TEST`, `SPIDER_ENTRANCE_TEST`, `SPIDER_WELCOME_SHOT`, `SPIDER_WIDGET_TEST`, `SPIDER_MINIMIZE_TEST`, `SPIDER_SPIDERS_TEST`, `SPIDER_CHAT_TEST`, `SPIDER_VOICE_EVAL`, `SPIDER_HABITAT_{CAMERA,INPUT,TEST,SHOT,BUILD,CURIOUS,PLACES,ECOLOGY,TOUR,OPEN}`, `SPIDER_WEATHER[_SHOT]`, `SPIDER_PAGE_TEST`, `SPIDER_TIMING`, `SPIDER_FRAMES`, `SPIDER_STATS`, `SPIDER_OPEN_TIMING` | Port the pattern: env var starts a scripted run, prints `[ok]/[FAIL]`, restores settings, quits. Test hooks suppress the habitat tour and mute music. |

### 20.1 Method rules learned the hard way
- **A/B against a baseline built from a *copy of the sources*,** not just git HEAD when the tree has uncommitted work. Seeded runs are frame-exact; dictionary-order randomness makes unseeded A/Bs noisy — use deterministic hashing/seeded RNG and compare *rates* across ≥ 4–8 seeds.
- **"Calm" must leave the spider byte-identical:** weather calm, habitat features gated on `eco`/`ecology` nil, body-language off — each new feature is gated and A/B'd against the previous build with identical frame dumps.
- Any leg change: flat dumps identical at all 5 sizes (0.62, 0.78, 0.95, 1.2, 1.55) and all leg styles; corner worlds improve.
- The owner judges what is **drawn**, with films. Metrics alone passed rounds that still looked wrong. Always produce close-up film strips for the owner.
- Perf: `SPIDER_TIMING` per-phase ms; `SPIDER_FRAMES` per-second frame meter (frames, busy mean/worst, > 12 ms updates, longest gap); trap: some test hooks force synchronous map building (`syncMaps`), so their open timings include an ~80–170 ms main-thread trace — not what users see.
- Pitfall: a test app launched from a terminal can sit behind other windows, so the tank pauses animations — shots set `debugKeepAnimating`.
- Real-OS input tests (scrolls, clicks, window moves) need scripted native-event tools; browser-automation clicks via debug protocols never reach OS-level input monitors.

### 20.2 Release gate (suggested)
Sim all-ok (except known flakes at base rate) · jerk < 2/min · leg-check flat identical · draw-radius cliptest · contact sheets match Mac · 30-minute soak on desktop: CPU ≈ 15% active / ≈ 4% resting, memory flat · habitat soak 30 minutes · multi-monitor mixed-DPI pass · fullscreen game/video pass · lock/unlock pass.
---

# PART K — APPENDICES

## Appendix A — macOS → Windows API mapping

| Concern | macOS | Windows |
|---|---|---|
| Overlay window | `NSPanel` borderless non-activating, `.floating`, `ignoresMouseEvents`, all Spaces | `WS_POPUP` + `WS_EX_LAYERED` + `WS_EX_TOPMOST` + `WS_EX_NOACTIVATE` + `WS_EX_TOOLWINDOW` (+ `WS_EX_TRANSPARENT` while click-through); DirectComposition or `UpdateLayeredWindow` |
| Click-through toggle | `window.ignoresMouseEvents` | `SetWindowLong` `WS_EX_TRANSPARENT` or `WM_NCHITTEST → HTTRANSPARENT` |
| Window list | `CGWindowListCopyWindowInfo` | `EnumWindows` + `GetWindowLong` + `IsWindowVisible/IsIconic` + `DwmGetWindowAttribute(DWMWA_CLOAKED, EXTENDED_FRAME_BOUNDS)`; or `SetWinEventHook` |
| App identity | pid/bundle id | pid → `QueryFullProcessImageName`; AppUserModelID |
| Minimize detection | bounds-shrinking heuristic | `EVENT_SYSTEM_MINIMIZESTART/END` |
| Full-screen | window covers display / hidden desktop | `SHQueryUserNotificationState`, rect tests |
| Dock | AX / estimated tiles | `SHAppBarMessage(ABM_GETTASKBARPOS, ABM_GETSTATE)` |
| Menu bar / notch | `visibleFrame`, `safeAreaInsets` | none |
| Notification banners | Notification Center windows | shell toast window probe (no `UserNotificationListener`) |
| Screen capture | `CGWindowListCreateImage` | `Windows.Graphics.Capture`, `PrintWindow`, `BitBlt` |
| Corner radius | measured from capture | `DWMWA_WINDOW_CORNER_PREFERENCE` / 8 px Win11 |
| Pointer position | `NSEvent.mouseLocation` | `GetCursorPos` (+ raw input for fast moves) |
| Global scroll/click | `NSEvent addGlobalMonitor` | `SetWindowsHookEx(WH_MOUSE_LL)` |
| Esc hotkey (only while toy on pointer) | Carbon `RegisterEventHotKey` | `RegisterHotKey` |
| Display clock | `CADisplayLink` 60 Hz | `DwmFlush`/waitable timer synced to vblank |
| Retained animation | Core Animation layers, `CATransaction` | DirectComposition visuals or your own scene graph |
| Particle emitters | `CAEmitterLayer` | custom particle system |
| 2D drawing | Core Graphics | Skia / Direct2D |
| Text | Core Text, SF | DirectWrite, Segoe UI |
| Tray | `NSStatusItem` + `NSPopover` | `Shell_NotifyIcon` + a custom popup window |
| Launch at login | `ServiceManagement` | Run key / StartupTask |
| Battery / Low Power / charger | IOKit.ps, `isLowPowerModeEnabled` | `GetSystemPowerStatus`, Battery Saver, `RegisterPowerSettingNotification` |
| Lock/unlock | screen-lock notifications | `WTSRegisterSessionNotification` |
| Volume | Core Audio property listeners | `IAudioEndpointVolume` |
| Brightness | DisplayServices | WMI / DDC |
| Music tap | Core Audio process tap (14.2+) | WASAPI loopback + session enumeration |
| FFT | Accelerate `vDSP` | KissFFT / pffft |
| Settings | `UserDefaults` (note: `defaults` CLI can see the wrong store for ad-hoc builds) | JSON in `%APPDATA%` |
| Update | Sparkle (EdDSA) | WinSparkle / Velopack |
| Signing | Developer ID + notarization | Authenticode (EV / Trusted Signing) |
| Apple Intelligence | `FoundationModels` | Windows AI / local / cloud |
| Networking | `Network.framework` NWListener | any loopback WebSocket server |
| Per-process hash seed | Swift Set/Dictionary order | avoid order-dependence |

## Appendix B — Settings and persistence keys

Settings store (macOS `UserDefaults` keys; keep names): `scale, interactive, paused, hidden, followCursor, approachCursor, pounceOnCursor, webs, hammock (saved hammock), hammocks (enabled), traces, traceLimit, widgets, wildlife, wildFrequency, tankWildlife, visitors, visitFrequency, visitStay, learns, feelPower, feelWeather, feelCommotion, danceToMusic, showRain, toySounds, lowPowerOverride, climbPages, confine (box), inHabitat, welcomed, askedToSeePages, design (JSON SpiderDesign), memory, habitatKnowledge, habitat (current), habitatGlass, habitatCamera, habitatSpider, habitatWeather, habitatWeatherNow, habitatCurrentSave, habitatTourSeen, habitatDecorateTourSeen, spiderCurrentSave, legLayersByDepth`. Files: `Spiders/*.json`, `Habitats/*.json` (`.spiderhabitat` = same JSON), memory in settings.

## Appendix C — Constants index

World & physics: gravity −1950 · maxJumpSpeed 1250 · air drag `exp(−0.22dt)` · restitution `lerp(0.28, 0.72, bounciness)` · hardThrow (thrown-vs-carried threshold) · max throw speed 2700 · cornerRadius 38×scale · default window cornerRadius 26 · standoff 22×scale · scales 0.62/0.78/0.95/1.2/1.55 · walkSpeed 62 px/s @1 · strideLength 28 · swingDuty 0.34 · footJolt 26 000×scale · reachLimit 1.25 · reachShare 0.94 · longStride 45 · handoffTime 0.26 · crouchDrop 7.5 · hopTakeoff 2 · hopHeight 7 · landHold 0.5 · landAbsorb 0.35 · cinemaPace 0.6 · grabRadius 30×scale · interestRange 170 · pointerFresh 20 s · hover name tag 0.7 s · maximizedSlack 24.
Rendering: ground −22 · drawRadius 72 · windowSlack 68 · leanPivot (1,−8) · abdomen (−14,3) rx14 ry13 · head (9.5,0.5) r13 · ball egg 20×17 · rope 14 segments, substep 1/120, ≤6/step, 10 relax passes.
Timing: clock 60 Hz (30 low power) · dt clamps 1/240…1/20 (app), ≤1/30 (spider) · tracker 30/10 Hz · up to 28 windows · decision interval 1.0–3.4 s ÷ liveliness · weather check 20 min · memory save 60 s · knowledge save 60 s · music: 100 fps flux, 118 BPM prior, 3 s steady, 12 s tap close, 10 s reopen · bridge ports 47219–47221 · page look 1.5 s, 30 Hz scroll follow.
Hammock: sag 0.42/0.66/0.50/0.34 · strands 7/9/6/6 · give 10/16/8/12 · drape 2.4 s · wall anchor 0.62 down · 
Habitat: world clamp 3000–5600 × 1050–1600, 2.75×/1.35× display · camera ω 2.5, max 1600, return 90 s · nav spot spacing 30, turn 55, watchdog 14 s, noWay after 45 s for prey · hunger gates 180→40 s etc. (17i).

## Appendix D — Risk register (highest first)

| # | Risk | Mitigation |
|---|---|---|
| 1 | **Feel drift.** Walking/line/turn animation is the product; a faithful transliteration can still feel wrong. | Port the Swift algorithms rather than rewriting; keep the Mac build as oracle; film-strip A/B at 5 sizes; the owner judges *drawn* output. |
| 2 | **Overlay behavior on Windows** (topmost vs taskbar/Start/full-screen apps/games, click-through hit-test flipping, virtual desktops, DPI). | Prototype Stage 3.1 first; test over exclusive-fullscreen games (you will not be above them — cinema rules); test with multi-monitor mixed DPI. |
| 3 | **Habitat scope** (≈ 35% of code; layered AI phases). | Ship desktop first; habitat later in sub-stages; gate each layer. |
| 4 | **Art volume** (≈ 15.5k lines of procedural drawing, 38 hats / 30 extras / 20 markings / 250 furniture kinds) | Drawing shim keeps the code; verify with contact sheets; consider auto-transliterating the Swift drawing calls. |
| 5 | **Determinism across platforms** (libm differences) | Compare statistically; seeded A/B within a platform. |
| 6 | **Particles/weather** (no emitter layer) | Custom system with the macOS traps in 17b. |
| 7 | **Talking spider** (no equivalent backend) | Optional; ship dark. |
| 8 | **Toast detection, window cloaking quirks** (UWP, snapped/maximized flags, borderless full-screen) | Probe per build; hide behind settings. |
| 9 | **Performance of capture** (camouflage/page climbing) | Optional; off by default. |
| 10 | **Unity of the core across OS** (hash order, `NSScreen` creep) | Lint the core for OS calls; headless sim in CI on both OSes. |

## Appendix E — Suggested milestone plan (build order condensed)

| M | Stage | Deliverable | Rough effort (1 dev) |
|---|---|---|---|
| M0 | 0–1 | Decisions D1–D7 made; core library skeleton; math, springs, rope; settings; clock; headless runner | 1–2 wk |
| M1 | 2 | Window tracker + `SurfaceMap` + debug overlay (Windows, multi-monitor, DPI, taskbar) | 2–3 wk |
| M2 | 3 | Overlay windows, drawing shim, spider renderer in profile/front/turn, contact sheet (default look only first) | 4–6 wk |
| M3 | 4 | Attached mode, classic gait, corners, turning, carried by windows | 4–6 wk |
| M4 | 5, 6.1–6.4 | Pointer interaction + decision loop + core repertoire + posture table + moods | 4–6 wk |
| M5 | 7 | Jumping, falling, throw, landing, covered-escape | 3–4 wk |
| M6 | 8.1–8.7 | Silk, rappel, hang, climb, mantle, swing, scroll orders | 5–8 wk |
| M7 | 8.8, 9 | Hammock, peek-a-boo | 2–3 wk |
| M8 | 16 | Tray, panel, settings, Studio (all tabs), My Spiders, welcome, entrance, packaging | 6–8 wk |
| M9 | 3.6 | The whole option library (hats, extras, eyes, mouths, coats, patterns, leg styles) | 4–8 wk (can run in parallel with M3–M7) |
| M10 | 10–13 | Prey, toys, traces, memory | 5–7 wk |
| M11 | 14–15 | Sensing (cinema, power, weather, pop-ups, music), box, visitors | 3–4 wk |
| **MVP ship** | | **M0–M11 = desktop product** | ≈ 11–14 months solo; far less with the Swift core reused |
| M12 | 17a–17c | Tank world, camera, scenery, furniture, tracer | 8–10 wk |
| M13 | 17d–17i | Structures, nature, curiosity, nav, places, ecology | 10–14 wk |
| M14 | 17j–17l | Weather, window/decorate/My Habitats/tours | 5–7 wk |
| M15 | 18 | Talking spider, web pages, extension | 3–6 wk |

If the Swift core is reused (decision D1) the numbers for M1/M3–M7/M10/M11 and the model halves of M12–M14 shrink dramatically; the remaining work is the platform host, drawing shim, UI and the animated-layer scene. A pragmatic order if time is tight: ship M0–M8 + default look + a trimmed option library, then M10–M11, then the habitat.

## Appendix F — Source map (read the Swift here)

| Question | File (lines) |
|---|---|
| vectors, springs, rope, noise | `Math.swift` (412) |
| surfaces/loops/rebuild/resolve/dock/cinema | `Surfaces.swift` (1120) |
| window polling, minimize, banners, widgets | `WindowTracker.swift` (498) |
| state machine, physics, gait, decisions, silk, hammock, prey hunt, toys, everything behavioral | `Spider.swift` (23 219) — MARKs: External input 1421 · Frame update 2388 · Pointer as prey 2791 · Thoughts 3240 · Weather 3572 · Peek-a-boo 4695 · Habitat 4978 · Tank 5138–8431 · Rescue 8858 · Food 8917 · Toys 9547 · Traces 10212 · Silk line 10598 · Attached 11522 · Posture 11868 · Left to itself 12732 · Body language 12834 · Decisions 13413 · Jumping 14127 · Airborne 14332 · Dangling 14925 · Over the top 15290 · Hammock 16209 · Legs 17062 · Walking 19578 · Natural walk 20670 · Refined walk 20959 · On a line 21740 · Pose out 22605 |
| all drawing of the spider | `SpiderRenderer.swift` (4956), `Skin.swift` (810), `SpiderDesign.swift` (1238) |
| overlay windows, silk layers, hammock view, sprite shower | `OverlayWindow.swift` (883) |
| app delegate: tick, panel, menu, settings, tests | `AppDelegate.swift` (5942) |
| panel layout | `Panel.swift` (696) |
| Studio | `Studio.swift` (2047) |
| creatures | `Prey.swift` (2028) · toys `Toys.swift` (960) · traces `Traces.swift` (1436) |
| memory | `Memory.swift` (472) · visitors `Visitors.swift` (240) |
| system sensing | `SystemSense.swift` (324) · ears `Ears.swift` (372) · beat `Beat.swift` (555) |
| web pages | `PageLedges.swift` (626) · `WebPages.swift` (976) · `PageBridge.swift` (240) · `Extension/` |
| habitat | `Habitat.swift` · `HabitatObjects/Geometry/Structures/Pieces/Nature/Semantics/Knowledge/Places/Ecology/Nav/Camera/Overview/Scene/Window/Controls/Library/Tour/Atmosphere/Weather` · `Weather.swift` · art `HabitatArt/Items/NatureArt/HomeArt/PieceArt` |
| talking | `SpiderVoice.swift` (310) · `ChatPanel.swift` (269) |
| onboarding, bug report, updater, perf | `Onboarding.swift` · `BugReport.swift` · `Updater.swift` · `Perf.swift` |
| tools | `tools/*.sh` + subfolders (sim, legs, perch, film, jerk, pages, beat, ears, …) |
| owner's rules and traps | the macOS project's notes (memory files) summarized throughout this document |
