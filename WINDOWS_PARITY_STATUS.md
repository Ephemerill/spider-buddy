# Windows parity status

Evidence levels are defined in section 8 of [WINDOWS_DEV_WORKFLOW.md](WINDOWS_DEV_WORKFLOW.md):
**E0** missing or fallback · **E1** works, never compared · **E2** compared, differences listed · **E3** measured equal ·
**E4** live on both and looked at. Only E3 and E4 count as parity.

**Oracle:** Mac v1.0.1, `Sources` tree `7c878d73`. **Last reviewed:** 2026-11-06.

Two codebases are in this branch. **Swift** is the Mac's unchanged source compiled for Windows (`Sources/`, `src/SwiftShims`, `src/SwiftHost`). **C#** is the earlier port from the spec (`src/Core`, `Renderer`, `App`, `Tools`). The levels below are for the Swift path where it covers a feature, and otherwise the C# app's level, taken from `docs/windows/WINDOWS_PORT_AUDIT.md`. Which path is final is the owner's call.

## Foundations

| Item | State | Notes |
|---|---|---|
| Code safe in git | Done | `windows` branch, backed up on GitHub |
| Mac-to-laptop dev loop | Done | `lap` |
| Live desktop bridge over SSH | Done | `lap run`, `lap shot` |
| Mac oracle: traces, images | Done | `capture/` on the Mac, not in git |
| Mac oracle: reports, UI shots, recordings, data files | Not started | `docs/windows/MAC_HANDOFF.md`. UI shots need the separate bundle id first. |
| Trace and image compare tools | Done | `difftrace.py`, `paritytraces.py`, `diffimages.py` |
| Honest release gate | Not started | Plan 3.7: it passes a 39 fps run today |

## Behavior and physics (Swift)

Evidence: `tests/parity/parity-traces.md`, `tests/parity/parity-free-runs.md`.

| Feature | Level | Notes |
|---|---|---|
| Walk, gait, legs, corners, all 5 sizes | E3 | Trace-exact |
| Posture and 37 activities | E3 | Trace-exact |
| Air, jumps, throws, landings | E3 | Trace-exact |
| Silk, rappel, climb, swing | E3 | Trace-exact |
| Hammock, peek-a-boo, carried on a window, cinema | E3 | Trace-exact |
| Hunts, all 8 prey | E3 | Trace-exact |
| Pointer: watch, stroke, whip, fidget | E3 | Trace-exact |
| Brain and repertoire | E3 | 8 free runs of 240 s, frame-exact |
| Toys, traces, visitors, memory | E2 | Same code, compiled and linked; no scenario exercises them yet |
| Habitat behavior | E2 | Same code for geometry, places, nav and ecology; the tank itself is not running yet |

## Art (Swift)

Evidence: 768 of 770 images pass (work log).

| Feature | Level | Notes |
|---|---|---|
| Body, faces, legs, coats, gradients, living coats, markings, hats, extras | E3 | Every Studio option at 2 sizes |
| Poses, emotes, thought icons, weather coats | E3 | |
| Name tag and bubble text | E2 | Shapes match. The font is too light: needs a decision on what to bundle. |
| Creatures, toys | E1 | Same code, not diffed |
| Habitat items, scenery, weather | E0 | Art compiles later with the tank; needs a `CALayer` compositor |

## Desktop host (Swift proof of concept, `src/SwiftHost`)

| Feature | Level | Notes |
|---|---|---|
| Layered window, Skia straight into the DIB | E1 | Runs on the real desktop |
| Mac's `WindowTracker` on a real window list | E1 | DWM bounds, cloaking, layered alpha. Filter list is a first pass. |
| Hit-testing, clicks only on the spider | E1 | Owner has picked it up. Not measured against the Mac. |
| Scroll orders | E1 | Sign and touchpad scaling not checked against the Mac |
| Silk thread | E1 | |
| Frame rate | E1 | About 53 fps, target 60 |
| Redraw gating | E0 | Redraws every frame |
| Multi-monitor, mixed DPI | E0 | Primary monitor only |
| Prey, toys, traces, hammock, laser, visitors, box, rain layers | E0 | |
| Full screen, maximized | E0 | Tracker reports them; host does not pass zoomed screens on yet |

## UI

Nothing is on the Swift path yet. The C# forms exist at E1 and have never been compared.

| Screen | Level | Notes |
|---|---|---|
| Tray icon and menus | E0 | Right-click has only Quit |
| Panel, 7 pages | E0 | |
| Studio, 12 tabs | E0 | |
| My Spiders | E0 | |
| Welcome tour, first entrance | E0 | |
| Chat, bug report | E0 | |
| Habitat window and controls | E0 | |

## Sensing

| Sensor | Level |
|---|---|
| Battery saver, charger, lock/unlock, weather, volume, brightness, banners, music and beat | E0 |

## Later

| Item | Notes |
|---|---|
| New leg system v2 (Studio toggle) | Uncommitted on the Mac. After v1.0.1 parity, once it settles. |
