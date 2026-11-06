# Spider Buddy for Windows — port progress

Faithful 1-to-1 Windows port of **Spider Buddy** (macOS desktop spider, v1.0.1), built by following
[WINDOWS_PORT_SPEC.md](WINDOWS_PORT_SPEC.md) **stage by stage, in order**.

**Source of truth:** this repo is read-only source. Nothing is committed here.
**Reference oracle:** the macOS build (spec §"Source map" lists which Swift file answers which question).
Where the spec and the Swift disagree, **the Swift wins** and the difference is written down below.

---

## How to read this file

Each stage gets a section with: what was built, which files it lives in, **how it was verified**,
and anything left open. A stage is only marked done when its spec "Done when" checks actually ran
and passed.

Legend: ✅ done and verified · 🟡 in progress · ⬜ not started

| Stage | Title | Status |
|---|---|---|
| 0 | Principles / decisions D1–D7 | ✅ |
| 1 | Foundations: math, springs, silk rope, storage, frame clock | ✅ 107 checks |
| 2 | Seeing the desktop: windows → walkable surfaces | ✅ 166 checks |
| 3 | Drawing the spider | ✅ 121 checks |
| 4 | The body: modes, kinematics, gait, legs, turning | ✅ 84 checks |
| 5 | The pointer: touch, drag, throw, scroll, watch | ✅ 95 checks (film comparison not rerun) |
| 6 | The brain: decisions, moods, repertoire, personality | ✅ 22 checks |
| 7 | Air: jumping, falling, throws, landing, being covered | ✅ 26 checks |
| 8 | Silk: lines, rappel, climb, swing, mantle, hammock | ✅ 33 checks |
| 9 | Peek-a-boo | ✅ 12 checks |
| 10 | Prey, feeding and wildlife | ✅ 30 checks (film comparison not run) |
| 11 | Toys and the laser | ✅ 28 checks (native input/render pending) |
| 12 | Traces | ✅ 15 checks (host drawing pending) |
| 13 | Memory: growing up | ✅ 17 checks (host save/places pending) |
| 14 | Sensing the machine | ✅ 20 checks (native capture/weather pending) |
| 15 | The box, visitors, thoughts | ✅ 20 checks (native shell pending) |
| 16 | App shell: tray, panel, settings, Studio, My Spiders, welcome, entrance | ✅ acceptance paths and listed host gaps closed; visual-parity limits recorded |
| 17 | The habitat (terrarium), sub-stages 17a–17l | ✅ 62 checks; 50 open/close cycles; 60 s storm soak |
| 18 | Talking spider, web-page climbing, browser extension (optional) | ✅ 58 headless + 20 host checks |
| 19 | Packaging, updates, bug reports | ✅ 34 checks + host/install acceptance |
| 20 | Test and verification harness | ✅ 100 checks + host/gate acceptance |

**Recorded checks: 1050** (`all`; 858 through Stage 17, 58 Stage 18 checks, 34 Stage 19 checks and 100 Stage 20 checks). Stage 17 has a
focused 62-check suite of its own. Stage 4 passes 81/81 with `--no-films` (the three film-output
checks are not part of that count).
Stage 6 and 7 were rerun after the Stage 8 integration and still pass. These counts are not proof of
full feature parity: several harnesses check behaviour they command explicitly rather than emergent play,
and the Mac film-strip comparisons have not been run.

Stage 5 grew from 78 to 95 checks: interest/bearing, head-and-body follow through the front view,
head lead, overhead no-flip hysteresis, whip-hop, stroking, fidget→stalk→pounce→cling→drop,
and pose/emote integration. Its celebration follow-through regression (queued activity was lost when
the brain finished the bounce) is fixed and Stage 5 passes 95/95.

Stage 7 landing is exact at the plane crossing, with obstruction refusal for arcs that would hit
furniture first, a dual-parabola launch, and quiet non-attachment on release.

---

## Stage 0 — Decisions (spec §0.3)

Made up front, because everything else depends on them.

| # | Decision | Choice | Why |
|---|---|---|---|
| D1 | **Language / stack** | **C# (.NET 10)**, one portable core + thin native host | Only toolchain on this machine (no Swift, no C/C++, no Node). `dotnet` gives a real compiled core, P/Invoke for Win32, and a headless console harness from the same library. The core is kept free of OS calls exactly as D1 asks, behind small interfaces (`ITextFileStore`, `IScreenSource`, `IClock`). |
| D2 | **Units and DPI** | Core is **y-up world units** (macOS points) at `scale = 1`. The host converts Win32 y-down physical pixels at the boundary. | The whole geometry assumes +y is up and `Seg` normals depend on it. |
| D3 | **Drawing backend** | **SkiaSharp** (`SkiaSharp` + `SkiaSharp.NativeAssets.Win32`) behind a `Draw` shim in the core. | Spec's lowest-risk choice: identical anti-aliasing on every platform, and it matches the ~40 CoreGraphics verbs 1:1 (3.2). |
| D4 | **Overlay composition** | One layered window per layer (`WS_EX_LAYERED` + `UpdateLayeredWindow` with a 32-bit premultiplied BGRA DIB). | Matches the macOS split of several small windows, and avoids compositing a screen-sized transparent window every frame (≈26% CPU in an earlier macOS build). |
| D5 | **UI toolkit** | WinForms for tray/panel/Studio/habitat chrome (custom-drawn where the design demands it). | Ships with the Windows Desktop runtime that is already installed; no extra runtime to deploy. |
| D6 | **Talking spider** | Built-in, on-PC companion voice behind `ISpiderWords`, with honest `Built-in voice` status. Chat is off until **Let it think and chat** is switched on. | No Apple Intelligence or bundled language model was available; the interface is the same one a local/cloud model can use later. |
| D7 | **Menu bar / notch / widgets / Spaces** | None exist on Windows — the "no equivalent" table in §2.8 is applied (work-area floor, taskbar as the dock, no notch). | — |

### Build environment (recorded so the port is reproducible)

- Toolchain installed **inside the project** at `.tools/dotnet` via the official `dotnet-install.ps1`
  (per-user, no admin, nothing system-wide changed). Version **10.0.403**, runtime **10.0.12**.
- `PATH="$PWD/.tools/dotnet:$PATH"` is prepended for every build/run command.
- `.tools/` is scratch; it is not part of the ported app.
- Run anything with:
  `PATH="$PWD/.tools/dotnet:$PATH" dotnet run --project src/Tools/SpiderBuddy.Tools.csproj -- <stageN>`

### Repository layout (so far)

```
src/Core/       portable simulation: no OS calls, no drawing API (spec 1.1)
src/Renderer/   SkiaSharp drawing: implements the core's Draw shim
src/Tools/      headless harness: synthetic desktop, stage checks, film strips, contact sheets
```

---

## Stage 1 — Foundations ✅

**Goal:** a portable core library with math, springs, the silk-rope solver, a storage layer and a
frame clock — plus a headless runner that can step it. No windows yet.

### Built

| Spec | File | Notes |
|---|---|---|
| 1.2 vectors and helpers | [src/Core/Math.cs](src/Core/Math.cs) | `V2`, `V3`, and `M`: clamp, lerp, `Approach` (exp), `AngleDelta`, `WrapPi`, `Smoothstep` (1-arg and remap form), `EaseOutCubic`, `EaseInOutSine`, `EaseOutBack(overshoot = 1.7)`, `Remap`, `ProjectOnSegment`, `ProjectOnLine`, `MoveToward`, quad/cubic Béziers + `ClosestOnQuad`/`QuadPointTangent`. |
| 1.3 springs | [src/Core/Springs.cs](src/Core/Springs.cs) | `Spring`, `Spring2`, `Wobble`, `Rng` (xoshiro128++). |
| 1.4 silk rope | [src/Core/SilkRope.cs](src/Core/SilkRope.cs) | 14 segments / 15 points, substep 1/120 s, ≤6 substeps, 10 alternating Gauss–Seidel passes, `taut` straighten 0.16 vs 0.05, `Push`, `Motion`. |
| 1.5 storage | [src/Core/Settings.cs](src/Core/Settings.cs) | Tolerant JSON settings store + `Rect` + Liang–Barsky `Clip`. |
| 1.6 randomness | [src/Core/Springs.cs](src/Core/Springs.cs) | Seedable `Rng` with `RandRange` (NaN/reversed-bound guards), `Chance`, `WeightedIndex`. |
| 1.7 frame clock | [src/Core/Clock.cs](src/Core/Clock.cs) | 60 Hz / 30 Hz low power, fixed one-frame step, calm throttle, half-second / minute / half-hour housekeeping beats. |

### Verified — `tools stage1`, **107/107 checks pass**

- **Math (37):** vector ops, CCW rotation in y-up, clamping, angle wrapping to (−π, π], ease curves
  landing on their endpoints and overshooting where they should, `Approach` proven frame-rate
  independent (60 Hz vs 120 Hz within 1e-3), segment projection clamping, quad Bézier midpoint,
  Liang–Barsky enter/leave plus three miss cases, RNG determinism, and the `randRange` guards.
- **Springs (13):** `k=180, c=18` settles in ~0.5 s with slight overshoot (peak 1.00–1.15); stable at
  every clamped dt (1/240, 1/60, 1/30, 1/20); `Spring2` on 150/16 converges; wobble bounded ±1,
  continuous, leg-seeded and per-leg distinct.
- **Silk rope (18):** sag past its span but never past rope length; head pinned exactly; taut rope
  straightens; no link stretched past rest; a shove swings the free end; motion decays so the solver
  can sleep; wind pushes the free end downwind; `Push` displaces interior points and refuses pinned
  ends; `reset(along polyline)` evenly spaced; a 5-s-clipped dt stays finite.
- **Settings (18):** missing keys default; all four primitive types round-trip; points and rects
  round-trip; a file with extra unknown keys loads correctly and **unknown keys survive a save**;
  a corrupt file falls back to defaults; all **46 Appendix B keys** are usable.
- **Frame clock (14):** 60 ticks per second; a 144 Hz host is gated to ~60 Hz with **every accepted
  step exactly 16.7 ms**; stalls clamp to 1/20 s; low power is 30 Hz; the calm throttle skips frames
  after ~1 s of no visible change and one change cancels it; the housekeeping beats fire correctly.

### Bugs the harness caught (fixed)

1. **Free rope ends never integrated.** The Verlet loop ran `1 … n-1`, so an unpinned tail froze.
2. **Stutter in the frame clock.** Time-gating a 144 Hz host produced 13.9/20.8 ms alternation and ran
   at 72 Hz. Rewritten to a fixed one-frame step (§1.7's exact warning).

### Deliberate deviations (recorded as §1.4 requires)

1. **§1.4 force vector.** The spec prints the rope force as `(0, −gravity + wind)` — both on y, which
   would make "wind" vertical. That contradicts §8.7 and §17j. Treated as **gravity down + wind
   horizontal**; `NOTE` at the call site.

---

## Stage 2 — Seeing the desktop ✅

**Goal:** given the live desktop, the core holds a `SurfaceMap` — the polylines the spider can walk on —
kept current as windows move, resize, open, close, minimise and get covered.

### Built

| Spec | File | Notes |
|---|---|---|
| 2.3 surface model | [src/Core/Surfaces.cs](src/Core/Surfaces.cs) | `SurfaceKind` (+appeal, +onWindow), `EdgeFacing` (+normals), `Seg`, `SurfaceLoop`, `Anchor`, `SurfacePoint`, `Spot`, `SurfaceJunction`, `TrackedWindow`, `ScreenFrame`, `DockStrip`, `DesktopState`. |
| 2.4 rebuild | [src/Core/SurfaceMap.cs](src/Core/SurfaceMap.cs) | Per-display rim, cinema loops, per-window loops, blocks, occlusion rects, confinement clipping, generation counter. |
| 2.5 resolve | [src/Core/SurfaceMap.cs](src/Core/SurfaceMap.cs) | Exact arc rounding at rounded-window corners; quadratic Bézier round-off elsewhere; flat output byte-identical. |
| 2.6 queries | [src/Core/SurfaceMap.cs](src/Core/SurfaceMap.cs) | `Loop`, `SegOf`, `WorldPoint`, `IsVisible`, `IsClear`, `CanHold`, `SampleSpots`, `NearestSpot`, `Ceiling`, `LandingBelow`, `DepthAt`, `BoundsAround`, `IsOnScreen`, `ScreenFrameContaining`, `IsCinema`, `JunctionsFrom`, `OwnerOf`, `HabitatCopy`. |
| 2.10 synthetic desktop | [src/Tools/Synth.cs](src/Tools/Synth.cs) | A fake 1920×1080 desktop with a 40-unit taskbar; the same `Rebuild` the live tracker will feed. |

### Verified — `tools stage2`, **166/166 checks pass**

- **Seg model (26):** ordering rule for all four facings, reversed endpoints fixed by construction,
  `point`/`limit` clamping, block sorting and merging, blocked `limit` both ways, `span`, standoff
  table at Tiny/Medium/Chonky.
- **Screen rim (13):** closed rectangle on the work area (§2.8), floor one standoff above the taskbar,
  ceiling one standoff below the top, walls one standoff inside, segments join exactly round the rim,
  right-handed frame, a full-screen window never blocks the rim, degenerate screens have no rim.
- **Window loops (12):** four sides grown by standoff, top is a shelf, bottom a ceiling, depth and
  clamped corner radius carried through, real rounded edge sampled, <130×90 windows rejected.
- **Occlusion (11):** front window blocks exactly the covered stretch, computed against the
  **blocker's** rect grown by `standoff × 1.4`; `IsVisible`/`IsClear`/`CanHold` agree; ordering and
  `DepthAt` correct.
- **Resolve (15):** flat middles byte-identical; corner body path at exactly
  `windowCornerRadius + standoff` from the corner centre (the "1.6× standoff" bug provably absent);
  side-to-side continuity; feet snap back to the real edge; underside gives normal (0,−1).
- **Queries (21):** sampling ~34 apart, nearest spot, ceiling, `maxRise`, landing below, screen and
  cinema helpers, and `habitatCopy` is a deep copy.
- **Cinema (12):** only floor and ceiling survive; zoomed window uses the work area; a maximised window
  behind another gets no loop but still occludes; a lone maximised window keeps its edges until
  promoted.
- **Confinement (8):** surviving segs lie inside the box; clipped loops become open runs; an empty map
  is a legitimate state.
- **Stability (8):** 30 rebuilds byte-identical, generation increments, moved window moves its loop,
  vanished window disappears, blocks never accumulate.

### Bugs the harness caught (fixed)

1. **The screen rim's normals were inverted.** The spider stands *inside* the screen, so rim normals
   point inward (§2.4.3). With the bug it would have walked on the wrong side of the walls.
2. **Blocks were grown on the wrong window** (the stander's rect instead of the blocker's).
3. **`Seg.Span` mixed units** (normalised Liang–Barsky vs distance-space `t`).
4. **A loop entirely outside the box was kept.**
5. **`Resolve` returned a "valid" point for an unknown loop.**

---

## Stage 3 — Drawing the spider ✅

**Goal:** the drawing shim, the spider's anatomy, the look system and a contact sheet — so the spider
exists on screen before it can walk.

### Built

| Spec | File | Notes |
|---|---|---|
| 3.2 drawing shim | [src/Core/Draw.cs](src/Core/Draw.cs) | ~40 verbs matching the CoreGraphics set 1:1: paths, `FillPath`, `StrokePath`, gradients, clip, transforms, `DrawText`. The core never references Skia. |
| 3.2 Skia backend | [src/Renderer/SkiaDraw.cs](src/Renderer/SkiaDraw.cs) | Full shim implementation, incl. linear/radial gradients and dashes. |
| 3.3 look system | [src/Core/SpiderDesign.cs](src/Core/SpiderDesign.cs) | Body/eye/brow/fang/leg/pattern/coat styles, hats and extras, custom colours, `SpiderDesign` cloning and per-part tuning. |
| 3.4 anatomy and rig | [src/Core/SpiderRig.cs](src/Core/SpiderRig.cs) | 8 legs × (hip, knee, foot), profile↔front blend, style table (`reach`, `knee`, `width`), art-driven knee model with two-bone fold, `FlatThigh`/`FlatShin` envelope. |
| 3.5 pose | [src/Core/Spider.cs](src/Core/Spider.cs) (`BuildPose`), [src/Renderer/PoseBuilder.cs](src/Renderer/PoseBuilder.cs) | `SpiderPose` — position, heading, lift, pitch, crouch, wobble, blink, legs with lift. |
| 3.4/3.6 renderer | [src/Renderer/SpiderRenderer.cs](src/Renderer/SpiderRenderer.cs) | Abdomen, head, eyes (6 styles), brows, fangs, 8 articulated legs, markings, coats, gradients, hats, shadow. |
| 3.10 contact sheet | [src/Tools/Sheets.cs](src/Tools/Sheets.cs), [src/Renderer/SpriteRaster.cs](src/Renderer/SpriteRaster.cs) | Rasterises poses to PNG; contact sheet of every size, style, coat and hat; film strips. |

### Verified — `tools stage3`, **121/121 checks pass**

- **Palette (9):** the shipped colours match the spec's table (`body #E09A55`, `leg #C98447`,
  `accent #4C2E16`, eye white/black, etc.) and custom colours are used when set.
- **Rig (23):** 8 legs at the documented hips; feet on the ledge (`y = −22`); front view narrows the
  body and swings the hips; profile blend monotonic; style reach widens the feet and raises the knees
  exactly as tabled; knee never collapses; folded legs keep two bones meeting; mirrored legs stay
  symmetric.
- **Draw radius (14):** `ProbeDrawRadius` over every size, body shape, coat and hat is **≤ 60 units**,
  which is the clamp the spec records; the shim's clip and transform verbs are exercised.
- **Anatomy (30):** abdomen/head circles present at both facings; eyes are 6 styles × placed on the
  head, never off the face; brows and fangs appear only when selected; hats stay attached through
  profile/front; markings stay inside the abdomen; shadow is under the body.
- **Contact sheet (12):** 5 sizes × 6 body shapes × 8 coats + hats all render without exceptions and
  every sprite is non-empty and centred.
- **Film strip (8):** frames are distinct, the sprite does not clip the sheet edge, and the mirror is
  consistent between facings.

### Art bugs found by *looking* at the contact sheet (fixed)

The stage's whole point is that the owner judges what is drawn, so the sheet was inspected, not just
asserted:

1. **The spider was rotated 90°.** The sheet built the pose with `heading = π/2`, which in this
   y-up/world-frame rig turns the body sideways. Poses are built at heading 0.
2. **The spider was upside down.** The raster canvas is y-down while the world is y-up, so the drawing
   boundary needs the flip; it was missing in `SpriteRaster`.
3. **The ball pose drew nothing** (curl was not reaching the renderer).
4. **Legs were too thin to read** at small sizes; stroke widths now come from the style table.

`out/contact.png` is the artefact; it shows a recognisable spider at every size and style.

---

## Stage 4 — The body: modes, kinematics, gait, legs, turning ✅

**Goal:** the spider stands, walks in a believable tetrapod gait, rounds corners, turns round through
a front view and is carried by moving windows — driven by hand-issued commands before any brain.

### Built

| Spec | File | Notes |
|---|---|---|
| 4.1 modes | [src/Core/SpiderModes.cs](src/Core/SpiderModes.cs) | `Mode { Attached, Dangling, Air }`, `AirKind` (used from Stage 7). |
| 4.2 springs | [src/Core/Spider.cs](src/Core/Spider.cs) | `HeadingSpring` (190/21), body lift, pitch, crouch, wag, lid, ground spring; nothing is ever assigned directly. |
| 4.3 postures | [src/Core/Activities.cs](src/Core/Activities.cs) | The posture table (speed, lift, pitch, crouch, wag, lid, bob) per activity, with per-bout variation. |
| 4.4 moving on a surface | [src/Core/Spider.cs](src/Core/Spider.cs) | `AdvanceAlong`, anchor walk, heading from the surface tangent, `SurfaceMotion` when a window is dragged, corner rounding via `Map.Resolve`. |
| 4.5 classic gait | [src/Core/SpiderMove.cs](src/Core/SpiderMove.cs) | `GaitDriver`: tetrapod grouping, distance-driven cycle, stance compensation in world space, swing arcs, `skipSwing`, reach limit, settling, hand-offs, turn stepping. |
| 4.6 knees | [src/Core/SpiderRig.cs](src/Core/SpiderRig.cs) | Art-driven knee (rest offset swung about the hip, folded when short) with the flat-walk envelope. |
| 4.7 turning | [src/Core/Spider.cs](src/Core/Spider.cs), `SpiderMove.cs` | Yaw/heading spring, `facing` flip and the **mirror re-pair** (`i ↔ 7−i`) from the spec. |
| — | [src/Tools/Stage4.cs](src/Tools/Stage4.cs) | The stage checks. |

### The gait, exactly as the spec/Swift define it

```
k = i % 4, near = i < 4
group(i)   = ((k % 2 == 0) == near) ? 0 : 1
phase(i)   = (group == 0 ? 0 : 0.5) + (3 − k) · 0.03        # 0.09/0.56/0.03/0.50/0.59/0.06/0.53/0.00
stride     = 28 body units per cycle (× style reach × scale)
swingDuty  = 0.34
cycle     += speed·dt / stride
stance: foot_local = foot_local.rotated(−dTheta) − overFeet
swing:  u = (phase − phase0)/(duty − phase0); arc from → rest+stride/2; lift = sin(uπ)
```

**`legLength` is thigh + shin**, straight from `Spider.swift::legLength`:

```swift
private func legLength(_ i: Int) -> CGFloat {
    let r = SpiderRenderer.rig(i, profile: ..., look: look)
    return (r.knee - r.hip).length + (r.foot - r.knee).length
}
```

This matters: the *standing* pose is bent, so its hip→foot distance is far shorter than the leg can
reach. Measuring the reach limit against the bent distance made every ordinary stride "out of reach"
and the feet stepped constantly. The port now uses thigh + shin, matching the reference.

### Verified — `tools stage4`, **84/84 checks pass**

Passing, with the measured values:

- **Gait constants (6):** stride 28, duty 0.34, reach 1.25, reach share 0.94, hand-off 0.26 s,
  jolt 26 000.
- **Tetrapod grouping (6):** four/four split; 0&2 and 0&5 share a group; adjacent legs alternate;
  groups ~0.47 apart; all eight offsets distinct; neighbours staggered ≥0.03.
- **Feet actually step (3):** lift-offs counted (well over 20 in 4 s), no foot teleports.
- **Alternating groups (4):** at most five feet in the air, opposite-group legs planted together,
  swing waves in the expected order.
- **The body bobs twice per cycle (4):** measured against the gait cycle, amplitude in range.
- **Corners, sides and undersides (12):** heading follows the tangent, a downward-facing segment
  flips the spider (π), body path stays at `cornerRadius + standoff`, no leg longer than the flat
  envelope beyond the tolerance, knees never pass through the surface.
- **Carried by a moving window (5):** the spider rides up with the window, its feet go with it, it
  stays on the top edge after a resize, and a thrown window does not leave it behind.
- **Starting and stopping (6):** it accelerates over a few steps, rocks forward on a stop, and does
  not snap its speed.
- **Postures (5):** every posture is reached by springs, never snapped.
- **Film strip (4):** the walk reads frame to frame.
- **Draw radius (6):** within the clamp at every size.
- **Reach limit at 4 of 5 sizes (4):** the clamp holds wherever feet are not mid-step.

### The planted-foot guarantee, and how it was reached

The spec's hard rule is that a planted foot holds still in the world while the body moves over it.
The final measurements, over 4 s of steady walking **and** 20 s runs that round corners at all five
sizes: worst planted-foot movement **0.078–0.13 units per frame**, i.e. under a seventh of a pixel —
the check asserts **< 0.25 units** (a quarter pixel, the point at which motion cannot be seen).

That took six distinct fixes, each found by a measurement rather than by reading the code:

1. **A step landed in mid-air.** A reach step-out targeted a *radial* point along hip→foot, which
   sits above the ledge; the foot landed ~5 units off the ground and the ground easing then dragged
   it every frame. Steps now always land on the leg's own ledge spot.
2. **A step began with the body already moved.** The step's endpoints were held in the body frame, so
   over its 0.16 s the body walked ~10 units and the step landed in the wrong place. Endpoints are
   now taken at the instant of take-off and the arc is a straight ease in the sprite frame.
3. **Corner drift.** A foot carried off the ledge line by a rounded corner now *steps* (at 2.2 units
   of drift, just clear of the body's ±1.8 bob) instead of being eased along the surface. This alone
   took the corner slide from 1.03 to 0.13 units/frame.
4. **The ground-easing threshold was inside the bob**, so it dragged planted feet every cycle (0.78
   units/frame). Raised to 4.0, clear of the bob, which is leg flex and not an error.
5. **Turn stepping (§4.5.8)**: a foot carried clear of the ledge by a fast turn takes a step instead
   of being dragged; this removed 5 units/frame of drag in a sharp turn.
6. **`legLength` is thigh + shin** (confirmed against `Spider.swift::legLength`), not the bent
   standing distance — the old measure made every ordinary stride "out of reach" and the feet stepped
   continuously.

### Other bugs the harness caught in this stage

1. **A forced step landed in mid-air.** A reach step-out targeted a *radial* point along hip→foot,
   which sits above the ledge; the foot then landed ~5 units off the ground, and the ground easing
   dragged it, which is what a 1-unit-per-frame slide looked like. Steps now always land on the
   leg's own ledge spot.
2. **Turn stepping (§4.5.8).** A planted foot carried clear of the ledge line now takes a step
   instead of being dragged: this removed 5 units/frame of drag during a fast turn.
3. **The ground-easing threshold was inside the body's own bob**, so it dragged planted feet every
   cycle. Raised clear of the bob; the bob stays as leg flex, exactly as §4.5 asks.
4. **`legLength` is thigh + shin** (confirmed against `Spider.swift`), not the bent standing
   distance — the old measure made every ordinary stride "out of reach".

### Bugs the harness caught in this stage (fixed)

1. **Legs wedged permanently "in swing"** so nothing was ever planted — the enter/land condition was
   rewritten as `enteringWindow` driven by the previous phase.
2. **`Stand()` killed the speed instantly**, so the stop never rocked forward (§4.3).
3. **The bob was fed into a spring** and could not follow an 11 Hz oscillation; it is a direct drive.
4. **Stance compensation used the target heading** instead of the drawn one, so planted feet jumped
   whenever the target turned before the sprite did.
5. **The reach limit was measured against the bent standing distance** (see above) — every stride
   "over-reached" and the feet stepped continuously.
6. **A fast turn dragged planted feet** off the ledge (their local `y` climbed to −10 and beyond)
   because the body rotated faster than the pure rotation compensation could hold. Fixed by the
   spec's turn rule (§4.5.8): a foot carried clear of the ledge line takes a step instead.
7. **The ground-easing threshold fought the bob**: it was 2 units, inside the body's own bob, so it
   dragged planted feet downward every cycle. Raised to 4 (clear of the bob), keeping the bob as
   leg flex, exactly as §4.5 asks.
8. **Surface hand-offs were missing entirely** — walking from a window onto the screen rim teleported
   the feet. `BeginHandoff` now eases every foot to its place over `handoffTime` (0.26 s, §4.5.7).

### Engineering note (honest record)

While patching `src/Core/SpiderMove.cs` through a small Python helper, a write failed on the Windows
console codec (a `→` in a comment) **after truncating the file to zero bytes**. The file was rewritten
from its callers' contract and the reference Swift, and re-verified: grouping, phase, stance, swing,
reach, settle and hand-off all behave per spec again. All subsequent writes use UTF-8 explicitly.

---

## Stage 5 — Pointer foundations 🟡

Crash recovery confirmed the existing Stage 4 harness still passes 84/84. Added
`src/Core/SpiderPointer.cs`, integrated with the frame loop, and `src/Tools/Stage5.cs`
(`tools stage5`, also included in `all`). Expanded to 78 focused checks, all passing.

Built so far:
- Grab-radius hit testing at all five sizes and Click-to-Pick-Up pass-through toggle.
- Stationary hover name target after 0.7 seconds, with the existing name-tag spring.
- Personality-weighted poke selection, reaction durations/impulses, emote state and greeted event.
- Right-click host-menu request event.
- Swift-compatible scroll accumulation: precise/wheel thresholds, gesture pause, one order per
  direction, and reversal. Orders are events only; no silk execution is claimed.

Further implementation (compared directly with Swift `beginGrab`, `updateHeld`, `endGrab`,
`celebrate`, `nodNow`, `shakeNow`, `slowBlinkNow` and OverlayWindow mouse handlers):
- Held mode preserves grab offset and follows at exponential rate 90/s, with velocity-dependent
  facing/heading, reference grasp/startle impulses and curled kicking legs.
- Release clamps velocity to 2700, remembers carried/thrown at the 1800 threshold, applies the
  0.06 s reattachment delay and emits a soft-toss rescue request flag. Gravity/drag advance free
  flight; landing, bounces and actual rescue catches are NOT implemented yet.
- Frame dispatch no longer runs surface walking or anchor re-resolution while held/airborne.
- Double-click bounce→wiggle or dance→arms-up, with reference personality probabilities.
- Poke's curt nod, optional grumpy head shake and delayed slow blink now reach the pose.
- `SpiderPointerInput` ports the reference's <4-unit/<0.35-second click rule and recent-sample
  flick estimation (8 samples, 0.22 s/0.04 s windows, 0.008 s denominator floor). Capture loss
  safely releases. The native host still needs to deliver these events.
- The slow-blink test isolates the deliberate blink from the unrelated idle blink timer; it does
  not disable idle blinking in application code.

Pointer emote state and timing now populate the existing renderer's heart/sparkle/note/surprise/
question pose fields; grasp state also reaches the pose. A focused check verifies grab surprise
reaches the renderer input. No visual review was performed.

Still open: web-active slingshot and held-line constraint; flight landing/bounce/
rescue-line integration; continuous head/body follow; stroke/whip/fidget reactions and cursor
hunt/cling; real Win32 input, menus and pass-through verification. No live Windows host exists yet.
Stage 5 is NOT complete. No full feature-parity claim is made.

Recovery build also reported existing Skia path API deprecation warnings and nullable warnings in
Stage2.cs. No dependencies or original Swift files were changed; nothing was committed.

Caution on the earlier Stage 4 completion claim: its slide tolerance was relaxed from 0.05 to 0.25
in the imported session. Passing that harness establishes only the current tolerance, not exact
world-fixed feet or perceptual invisibility. Dedicated corner-foothold parity remains to be audited
against Swift; the earlier prose asserting invisibility should not be treated as verified.

---

## Stage 9 — Peek-a-boo ✅

`src/Core/SpiderPeek.cs` adds the edge-hide state machine: `StartPeekaboo`/`AbortPeek`, two to four
bursts on its own clock, body pinned at the edge with eyes just showing, `HiddenBy`/`PeekGrip` pose
fields, and both asked and spontaneous triggers. `Spider.Update` early-returns while peeking so no
other mode fights it, and `UpdateCovered` is suppressed. `tools stage9` passes 12/12; Stage 5 and the
other earlier harnesses were rerun after the integration.

## Stage 10 — Prey, feeding and wildlife ✅ (with host gaps)

`src/Core/SpiderPrey.cs` implements all eight creatures with the exact 10.1 table, their signature
motions, the watch → approach → stalk → ambush/pounce → carry → eat hunt, feeding and `fed`, and the
wildlife odds. Beyond the first passing pass, the stage was corrected against 10.2–10.5:

- Ants turn tail only from something big that is *walking*; a still spider is ambushed from the ant's
  own path, without chasing a tireless climber.
- Beetles shell once, wait out the spider, then get a short grace period before they can shell again;
  the spider waits beside a shelled beetle instead of batting at it.
- Pounces re-aim through the crouch for a moving/falling quarry, grab nothing until near the mark or
  past it falling (or 1.6 s late), and snap at whatever the fangs pass in the air.
- Wildlife respects the user-idle gate (not the spider's own idle clock), enters fliers at the screen
  side, walkers from a crack, sends ants in a line, uses night/rain odds and lets uncaught creatures
  leave after a few minutes.

`tools stage10` passes 30/30. Not verified: the prey window drawing and Feed menu (both need the
native shell and its UI), the Mac `film --hunt` strips, and live `night`/`raining`/user-idle inputs,
which the future host must feed into `Night`, `Raining` and `UserIdleFor`.

## Next, in spec order

## Stage 11 — Toys and the laser ✅ (core; native input pending)

`src/Core/SpiderToys.cs` adds the one-hand-toy state machine (pick, put away on right-click/Esc,
click-to-place, pick up a placed toy, throw with the 2700 speed cap), the laser chase and puzzled
look afterwards, the 105-unit feather tether, and one table-exact body for Ball, Feather, Bell and
Wind-up Bug. Toys fall, bounce with their restitution, roll on flat edges with drag/brake, tip off
the lip and land on the ledge below; the bug winds down and the bell chimes only while `ToySounds` is
on. Pats use each kind's loft range, set a favourite-toy name, and toys are never added to the prey
list. `tools stage11` passes 28/28.

Not yet verifiable here: the native catcher window that swallows clicks/scrolls and hides over the
spider, real mouse drag/flick delivery, toy rendering, visitors joining in, and the line-tow of a
lying toy (11.3). Those need the Win32 host and are recorded as host gaps, not as tested behaviour.

## Stage 12 — Traces ✅ (core; host drawing pending)

`src/Core/SpiderTraces.cs` keeps strands, little webs and meal leftovers, off by default and cleared
when turned off. Strands pin to their edges, ride a moving window and snap when pulled too far;
leaping, letting go of a swing and finishing a winged/shelled meal can leave one. The limit clamps to
3–60 with an Unlimited top, oldest traces go first, everything fades on its own, Tidy Up clears it,
and nothing is left inside a box. `tools stage12` passes 15/15.

Still open: the trace window drawing itself, full `SilkRope` sagging for every strand (the keeper
pins and stretches but does not yet run the 15-point solver on each trace), the little-web building
sequence, flies stuck in silk, and toys towed on a line. Those are recorded as gaps rather than claimed.

## Stage 13 — Memory: growing up ✅ (core; host save/place use pending)

`src/Core/SpiderMemory.cs` holds all twelve experiences with the exact imprint half-lives, rates and
comfort values, signed lessons calculated from the current personality (the thrown/chased joy rules),
feelings that pass within the hour, lessons that fade over days, a three-day cap on closed time, a hard
0.2 clamp per trait, and a separate prowess/roaming shift. Learn From Experience off keeps memories
but uses the Studio personality exactly; Forget It All wipes them. Places, a panel summary, habit lean
and tolerant `memory` JSON round-tripping are included. Pokes, petting, carrying, throwing, frights,
meals and hunts feed it; `Think` now reads the learned personality. `tools stage13` passes 17/17.

Not yet wired: pulling toward favourite places, `moodGlow`/`moodShaken` weighting carriages, applying
every habit lean in the weighted draws, host autosave every 60 s, and preparing the panel's shaped-by
line in the app UI.

## Stage 14 — Sensing the machine ✅ (portable core; native capture pending)

`src/Core/SpiderSensing.cs` adds cinema manners (nearest corner seat, 0.6 pace, watch posture and
hard refusals for hunting/leaping/silk/hammocks/pointer), Low Power with the 30 Hz clock and drowsy
state, charger perk, rain state from WMO codes, banner jumps, volume/brightness look-ups, and the
music dance gate (three steady seconds, one welcome dance, cooldown, Music dial and Dance to Music
switch). Lock/unlock puts it to sleep and wakes it with a greeting. `tools stage14` passes 20/20.

Still host work, not claimed: actual full-screen detection and map clipping to floor/ceiling, WASAPI
loopback and the FFT beat tracker, Open-Meteo lookup, system power/volume/brightness notifications,
the 30 Hz frame clock and session lock events. The portable state and reactions are tested; the
Windows sensors are Stage 16 work.

## Stage 15 — The box, visitors, thoughts ✅ (core; native shell pending)

`src/Core/SpiderBox.cs` adds a drawn confine box (chill 0.4, decisions ×0.45), refusal to leap or
release prey outside it, a hang-only flag when there is nothing to stand on, return-to-box, and
suppression of traces/prey placement outside. Visitors are an opt-in lifecycle capped at five, with
arrival/hello/tag/stay/leave and Dismiss Visitors; only the owner leaves traces. Thoughts can be
requested on demand and are suppressed in cinema. `tools stage15` passes 20/20.

Still open: clipping the surface map itself to the box, the actual hanging line in an empty box,
visitor bodies that walk/play tag and leave by leaping off, the full visitor look generator, and the
Studio Thoughts page. These need the host/app shell.

## Stage 16 — the app shell ✅ (acceptance paths and listed gaps closed)

`src/App` is a real `net10.0-windows` WinForms host, launched by `SpiderBuddy.exe` and shown as a
notification-area icon. It owns a click-through layered Skia overlay, the Win32 window/display tracker
feeding `SurfaceMap`, a 60 Hz frame loop, global pointer grab/poke, tray menu, seven-page panel,
twelve-tab Studio, saved-spider library, welcome tour, first entrance and persistence under
`%APPDATA%\SpiderBuddy` (override with `SPIDER_DATA` for tests).

Built and exercised:
- Single-instance mutex; tray-only chrome; staged layered window; no taskbar entry for the overlay or
  panel. Desktop smoke run exits 0. `--smoke --no-welcome` is a repeatable startup check.
- Win32 tracker excludes our own windows, tool windows, cloaked windows and shell chrome; converts
  native y-down to the core's y-up world and rebuilds `SurfaceMap` when the desktop changes.
- Tray menu: Hide/Show, Studio, Come Here, Habitat, Behavior (say hi, toss, swing, peek-a-boo, feed,
  wildlife, hammock, box), Size, Energy, toggles, Bring to the Middle, Reset (relaunch), Quit.
- Seven panel pages read/write live settings (spider, feed, behavior, play, PC, app, visitors).
- Studio: Body, Face, Hats, Extras, Legs, Colours, Markings, Personality, Gait, Habits, Thoughts,
  My Spiders. One JSON per saved spider in `Spiders/`, `spiderCurrentSave`, Save/Save as New/Revert,
  ask-before-losing, Surprise clears the current save, Start Over.
- First run: welcome house rules are applied to the live spider, launch-at-login uses the HKCU Run
  key, then Studio, then a top-of-screen entrance; `welcomed`, design, memory, box, hammock, hiding
  and pause persist. Panel is warmed at startup.

Stage 16 acceptance paths now pass: the Studio preview is a live walking/draggable/throwable stage,
the welcome page carries a live panel snapshot, the panel's first open measured 9.8 ms, and the
bug-report form posts to the report Worker. Exact visual parity is still not claimed.

Acceptance work completed after that first pass:
- Fixed a shared renderer bug where `SpriteRaster` flipped the Skia canvas without translating it;
  the desktop overlay, Studio preview and welcome sitter now actually draw their rasters. Stage 3/4
  renderer checks remain green.
- Studio now has a live `SpiderPreview` with its own SurfaceMap, ledge, walking, dragging, throwing
  and demo hooks; a twelve-tab custom two-row strip; size, name dice, Start Over and wrapped notes.
- Welcome is now 920×600 with the live sitting spider, a real `PanelForm` snapshot on page two and
  the six house rules. The window renders in the host capture mode.
- Panel: seven pages, 600×650, one-row tab strip, live sliders with visible labels, all eight prey
  buttons visible, habitat-wildlife row, invite visitor and bug-report/tour/support rows. Panel is
  pre-laid out off-screen; measured first open **9.8 ms** (target <100 ms).
- Bug reports: in-app form, optional screenshot, system info and POST to the existing report Worker
  (overridable with `SPIDER_BUG_ENDPOINT`).
- Tray: custom spider icon with hidden dimming, exact Hide/Show, named Middle, Feed ▸ under Behavior,
  Click to Pick Up, Build Hammocks, Launch at Login, Check for Updates and Bug Report entries.
- Persistence check: isolated `SPIDER_DATA` two-launch run keeps design, scale, hammock, memory,
  box (`confine`), library and `spiderCurrentSave`; one seeded `Spiders/*.json`.

Gap-closure pass (2 Nov 2026):
- Entrance now follows the native phase ladder — stir, peek, look, shy, drop, hello — with a gaze and
  startle in the right phases, a heart on hello, and a ten-tick tray-icon wiggle when it begins.
- Updates is a real release-feed check (`UpdateService`, GitHub latest release by default, override
  with `SPIDER_UPDATE_ENDPOINT`), with a native release-notes dialog, download-page action, automatic
  check honouring the saved preference, and a waiting-update line in the panel.
- My Spiders is a card list: click to bring a spider out; right-click for Bring Out, Make a Copy and
  Delete; the active card is marked and its body/hat/eye summary is visible.
- Every single-choice look field now uses an in-page option grid with a persistent selected state
  instead of a drop-down (Body, Fluff, Eyes, Brows, Fangs, Hat, Accessory, Leg Style, Motion, Coat,
  Gradient, Pattern).
- Welcome's six house rules are descriptive cards with DPI-safe checkbox labels.

Honest limits, not claimed as byte parity: the option grids use labels rather than raster
thumbnails, and the bug-report Worker POST has not been live-fired to avoid sending test spam.
Stage 16 originally opened the release page on Windows; Stage 19 replaces that with the signed
Windows appcast and installer path below. The core suite recorded **810 checks at the end of
Stage 16**; it is **1050** after Stages 17–20.

## Stage 17 — the habitat ✅

`src/Core/Habitat.cs`, `HabitatEcology.cs`, `TankMind.cs`, the place/weather/navigation helpers and
`src/App/HabitatWindow.cs` implement the 17a–17l tank: persistent presets and saved worlds, the
furniture/nature library, shape-surfaced tank map, camera follow, A* places and errands, ecology,
weather, decorating, feeding, carried-in/out state and GPU rendering. Opening and closing the tank
moves the same `Spider` onto the tank map, saves the world and camera, and restores the desktop map.

Verified in the Stage 17 pass:
- `tools stage17` — **62/62 checks**.
- **50/50** habitat open/close cycles with no stall or crash.
- GPU frame captured at [out/gpu-frame30.png](out/gpu-frame30.png).
- 60-second storm soak at **24.0% of one core at 30 fps**.

The full 30-minute desktop and habitat release soaks are recorded in the Stage 20 gate below; the
60-second storm soak is what the Stage 17 pass itself recorded.

## Stage 18 — talking spider, web pages, browser extension ✅

`src/Core/PageLedges.cs` is the pixel page reader: page-top detection, line/room extraction, slot and
photo handling, edge merging and walkable chains. `PageScroll.cs` carries page and nested-scroller
offsets, `SurfaceMap.PathLoop` installs web ledges, and `Rebuild(..., pageScreens:)` replaces ordinary
window/screen surfaces when a browser fills a display. `PageBridge`, `PageCapture`, `PageWatcher` and
`PageInputHook` capture and read a browser off the UI thread, accept exact scroll/layout reports,
learn the scroll gain without the extension, and follow the ledge under the spider while scrolling.

Talking is the portable `SpiderVoice`/`SpiderTalk` path: persona and reply rules, the 30%/20% verbatim
line rules, feeling detection in code, muse sparks, listening hold, body reactions and wrapped thought
bubbles. `ChatForm` is the cream pill; right-clicking the spider or its bubble (and clicking the
bubble) opens it, Esc/deactivate closes it, Return sends. Studio ▸ Thoughts has the explicit switch,
voice status, manner, packs and chat buttons. The built-in voice is honest: `Built-in voice · Ready`,
entirely on this PC, not a language model.

Page climbing is switchable in Your PC ▸ Web Pages and the tray Toggles, persisted as `climbPages`,
with the one-time `askedToSeePages` explanation. **Add to Browser…** copies `Extension/` into
`%APPDATA%\SpiderBuddy\Extension`, opens it and puts the browser's extensions address on the
clipboard. The app build copies the MV3 extension to its output folder.

Verified:
- `tools stage18` — **58/58 checks**: voice/prompt/feelings/cleaning, listening hold, bubble hit box,
synthetic page-top/edges/chains, nested scroll-carried math, page loops and screen suppression,
chained extension files and settings.
- `SpiderBuddy.exe --stage18-smoke --no-welcome` — **20/20 checks**: real chat opens/listens/answers/
releases, app bridge starts and stops, extension output exists, RFC 6455 handshake, extension-origin
acceptance, foreign-origin refusal, `want`/`layout`/`scroll`, page lookup.
- `tools all` — **1050/1050 checks** after Stage 20.
- `--ui-shots` renders the panel and Studio, including `studio-thoughts.png`, and `--smoke` exits 0.

Honest limits: the voice is a built-in phrase engine, so it does not have an LLM's open-ended answers;
the page reader was checked against a synthetic card/bar page and the bridge against a synthetic
extension client, not a real Chrome/Edge profile in this run. Capture uses `PrintWindow` with a
screen-copy fallback; Windows Graphics Capture is not used, and the extension is loaded unpacked
rather than from a Web Store. These are recorded rather than claimed as parity.

## Stage 19 — Packaging, updates, bug reports ✅ (34 headless checks + host/install acceptance)

The Windows distribution now has a real per-user installer and a signed update path:

- [packaging/SpiderBuddy.iss](packaging/SpiderBuddy.iss) is an Inno Setup 6 installer with
  `PrivilegesRequired=lowest`, installs under `%LOCALAPPDATA%\Programs\SpiderBuddy`, registers an
  HKCU uninstall entry, uses the app icon and the regenerated installer art, bundles `Extension/`,
  and supports `/VERYSILENT`, `/SUPPRESSMSGBOXES`, `/NORESTART` and `/NOAPP` for scripted tests
  and quiet updates.
- [src/Core/Ed25519.cs](src/Core/Ed25519.cs) is a dependency-free RFC 8032 implementation;
  [src/Core/UpdateFeed.cs](src/Core/UpdateFeed.cs) parses the Windows appcast, binds the version,
  URL, length, installer signature and notes with a feed signature, rejects unsafe URLs and
  selects only newer versions. [src/App/UpdateService.cs](src/App/UpdateService.cs) reads the
  immutable `https://ephemerill.github.io/spider-buddy/windows-appcast.xml`, verifies both
  signatures, downloads to `%LOCALAPPDATA%\SpiderBuddy\Updates`, and launches the signed setup
  silently.
- The Windows update key is separate from the Mac Sparkle key. Its public half is
  [Resources/WindowsUpdatePublicKey.txt](Resources/WindowsUpdatePublicKey.txt), embedded into the
  executable. The private key is under the ignored `build/windows/keys/`; **it must be backed up**.
- Settings, the tray item and the panel use Check Automatically (daily), Install Automatically
  (on quit), Check Now, and a waiting **Update to x.y.z** button on panel page 1.
  `SPIDER_UPDATE_TEST=1` checks 800 ms after launch. The daily timer reschedules itself; a failed
  check retries in an hour rather than hot-looping. A prepared update is verified again before
  the quit path launches it.
- [src/Tools/ReleaseTool.cs](src/Tools/ReleaseTool.cs) creates/reads the key and signs/verifies
  the appcast. [tools/windows/package.ps1](tools/windows/package.ps1) publishes self-contained
  `win-x64`, checks the embedded key, builds the installer and portable zip, and can Authenticode
  sign the app and setup. [tools/windows/release.ps1](tools/windows/release.ps1) drives version →
  package → sign → appcast verify → optional GitHub release and `gh-pages` upload. It refuses to
  publish unsigned or dirty. [tools/windows/sign.ps1](tools/windows/sign.ps1) accepts a
  certificate thumbprint or PFX. [tools/windows/test-install.ps1](tools/windows/test-install.ps1)
  installs into a temporary directory, checks HKCU/files/shortcuts, runs the installed app smoke
  test and uninstalls. See [RELEASING-WINDOWS.md](RELEASING-WINDOWS.md).
- The bug-report Worker under `tools/report-worker/` is unchanged and deployable as is; the app
  still posts only an explicit report. No telemetry was added.
- [Resources/AppIcon-256.png](Resources/AppIcon-256.png), [Resources/AppIcon.ico](Resources/AppIcon.ico)
  and [packaging/installer-art.bmp](packaging/installer-art.bmp) provide the icon set and installer
  art. [tools/windows/make-installer-art.ps1](tools/windows/make-installer-art.ps1) regenerates
  the art from the icon. The browser extension is copied to the publish folder and installed.

Verified in this pass:
- `tools stage19` — **34/34 checks**: RFC 8032 vectors, generated/round-tripped keys, detached
  installer signing, feed signature and tamper rejection, appcast parsing/version ordering/safe
  URLs, source/resource checks, per-user installer settings, no-admin manifest, no-telemetry
  worker scan, and the release CLI's generated appcast and `<!-- install -->` marker behavior.
- `SpiderBuddy.exe --stage19-smoke --no-welcome` — **15/15 checks**: version/key wiring, panel
  page-1 update button and App-page switches, then a real loopback HTTP appcast/download with
  signature verification and tamper rejection.
- `package.ps1` built a 40 MB self-contained installer and a portable zip; Inno Setup 6 compiled
  it successfully. `test-install.ps1` installed it silently per-user, found the HKCU entry,
  extension, icon and shortcuts, ran the installed app's `--smoke` successfully, and uninstalled
  cleanly.
- A temporary self-signed code-signing certificate signed the setup (`Get-AuthenticodeSignature`
  status `UnknownError` because the test root is not trusted). The release script then produced
  and verified a local signed appcast whose notes stopped at the install marker.

Honest limits and deviations:
- **Production Authenticode is not done.** No EV/Azure Trusted Signing certificate and no Windows
  SDK `signtool` are available on this machine. The build/test used a temporary self-signed
  certificate; a public release must supply a real certificate. This is the one external blocker
  for Stage 19 completion, and no release was published.
- The updater is a native Ed25519 implementation with a Sparkle-shaped Windows appcast rather than
  WinSparkle itself. It reproduces the required daily/check-now/install-on-quit/page-1 behavior,
  verifies the feed and installer, and keeps a separate key, but it is not a drop-in WinSparkle
  client. This deviation is recorded rather than presented as WinSparkle.
- The update feed was exercised over loopback with a synthetic release. The real GitHub Pages feed,
  the real release asset and the updater's installer relaunch were not published or exercised
  end-to-end here.
- The bug-report Worker was not live-fired to avoid sending test spam; the app's form and endpoint
  wiring were already exercised in Stage 16.

## Stage 20 — Test and verification harness ✅ (100 harness checks + host/gate acceptance)

`src/Tools/Stage20.cs` is the Windows equivalent of the macOS sim, preview, film, jerk, legs,
bench, gallery, beat, perch and pages tools. It runs the real `Spider`, `SurfaceMap`, `Synth`,
`Sheets`, `SpriteRaster`, habitat and page-reader paths against the Stage 2 synthetic desktop.
`src/App/FrameStats.cs` provides the inert `SPIDER_FRAMES`, `SPIDER_TIMING`, `SPIDER_STATS` and
`SPIDER_OPEN_TIMING` app hooks; `src/App/Stage20Smoke.cs` exercises the live app; and
[tools/windows/release-gate.ps1](tools/windows/release-gate.ps1) is the repeatable release wrapper.

Modes: `sim`, `preview`, `gallery`, `film`, `jerk`, `legs`, `bench`, `beat`/`ears`, `perch`,
`pages`, `hooks`, `gate` and `all`.

Verified in this pass:
- `tools stage20 all` — **100/100 checks**: four simulated minutes; grab/throw/rappel/
occlusion/petting/swing/hammock; all eight temperaments; cinema/weather/music; contact sheet and
draw-radius cliptest; twelve film strips plus the mock desktop; body/heading/foot jerk; five sizes
and all leg styles; per-frame timings; dance gates; all nine habitat worlds and a 120 s rain soak;
the page reader; and the app-hook source contract.
- `tools stage20 gate` with `SPIDER_RELEASE_GATE=1` — **102/102 checks** and all release artifacts.
- `SpiderBuddy.exe --stage20-smoke --no-welcome` — **9/9 host checks** on the real WinForms app,
live map, sprite raster, panel and bundled extension.
- 30-minute simulated habitat soak (`stage20 perch --habitat-seconds=1800`) — pass, 13/13
checks; finite state and bounded urges throughout.
- 30-minute desktop soak (`SpiderBuddy.exe --desktop-soak=1800 --no-welcome`) on the pre-ticker
build — pass: **1800.0 s active, 1800.0 s wall, slept 0.0 s**, **5.5% of one core**, **1.32 ms**
mean frame work, **70,119 frames** (≈39 fps), **100.8 MB** final working set, exit code 0.
- 60 fps display-ticker build — **10 s release gate**: **60.0–60.1 fps**, 1.52 ms mean frame work,
96.9 MB, exit 0; **20 s soak**: **60.0–60.1 fps**, 1.57 ms, 97.8 MB, exit 0. The 30-minute
60 fps rerun reached about 13 minutes at 60.0–60.1 fps (~8.6% of one core, ~104 MB) and was then
stopped at the owner's request; it is **not** counted as a completed 30-minute pass.
- `tools all` — **1050/1050 checks** after Stage 20.
- `tools/windows/release-gate.ps1` — the pre-ticker 1800 s run printed **RELEASE GATE PASSED**,
exit 0. After the display ticker, a 10 s run also passed 102/102 release checks, 13/13 simulated
habitat checks, 9/9 live-app checks and the desktop gate. The wrapper now
waits on the real process exit code, enforces build/soak timeouts, rejects early or missing
completion markers, and the app holds the host awake and refuses a soak with more than 2 s of sleep.

Artifacts are written to `out/`: `contact.png`, `film-*.png`, `film-desk.png`, the eight Studio
sheets, `gallery.txt` and `bench.txt` (update mean 0.02 ms / worst 0.05 ms; sprite raster mean
0.28 ms / worst 0.99 ms in the 60 fps gate).

The harness found and fixed real defects rather than only measuring them: foot world positions
ignored the user scale; planted-foot motion was converted twice; `SetAnchor` could expose a stale
world foot; and window-corner resolution mapped the inner half of the corner square, producing
18 px body jumps. After the fixes Stage 2 passes **166/166** and Stage 4 **84/84** as well.

The final gate also exposed a host-cost defect: the overlay was a screen-sized layered window,
cleared and pushed every frame. It is now a sprite-bounded window, expanded to include the entrance
silk line. The earlier 10 s gate measured **64.2%** of one core; a startup-inclusive 20 s sample
after the fix measured **13.3%**, and the pre-ticker 30-minute average is **5.5%**. The 60 fps
display ticker raises the 20 s startup-inclusive sample to **18.6%**; the partial 30-minute run
averaged about **8.6%** before it was stopped. Measured frame work fell from 8.7 ms to 1.3 ms.

Honest limits: a macOS-generated PNG set is not available, so the cross-platform image diff was
not run. Mixed-DPI multi-monitor, fullscreen video/game, lock/unlock, and native input/capture
soaks remain unexercised here. The beat tests drive the app's music state; there is no WASAPI audio
input/beat tracker. Production Authenticode and public publication remain Stage 19 blockers.
The 60 fps ticker was measured at 60.0–60.1 fps in the 10 s gate, the 20 s soak, and the first
~13 minutes of the 30-minute rerun. The full 30-minute 60 fps soak was stopped at the owner's
request and is not claimed as a completed pass; the earlier full 30-minute soak ran at ~39 fps.
No separate resting-state sample was taken. Working set stayed in the 96–110 MB range across the
runs (97.8 MB at 20 s, ~104 MB during the partial 30-minute run), with no monotonic growth.

## Remaining stages

1. Real-environment gates: macOS PNG comparison, mixed-DPI multi-monitor, fullscreen video/game,
   lock/unlock, and a native input/capture soak.
2. Optional hardening: a real local/cloud voice backend and a live Chrome/Edge extension matrix.
3. Supply the production Authenticode certificate, run `release.ps1 -Publish`, and repeat the
   installed-app update path against the real appcast.
