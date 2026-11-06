# Windows parity status

Evidence levels are defined in section 8 of [WINDOWS_DEV_WORKFLOW.md](WINDOWS_DEV_WORKFLOW.md):
**E0** missing or fallback · **E1** works, never compared · **E2** compared, differences listed · **E3** measured equal ·
**E4** live on both and looked at. Only E3 and E4 count as parity.

**Oracle:** Mac v1.0.1, `Sources` tree `7c878d73`. **Last reviewed:** 2026-11-06.

Starting levels come from `docs/windows/WINDOWS_PORT_AUDIT.md`. Nothing is above E2 yet because no Mac comparison had ever been run.

## Foundations

| Item | State | Notes |
|---|---|---|
| Code safe in git | Done | `windows` branch, backed up on GitHub |
| Mac-to-laptop dev loop | Done | `lap`, in the workflow doc |
| Live desktop bridge over SSH | Done | `lap run`, `lap shot` |
| Mac oracle tools compile and run | In progress | Written blind on Windows; first real compile under way |
| Compare tools (`parity trace`, `diff-trace`, `diff-image`) | Not started | Plan 3.2 |
| Honest release gate | Not started | Plan 3.7: it passes a 39 fps run today |

## Desktop host

| Feature | Level | Notes |
|---|---|---|
| Layered windows, no per-frame copy chain | E1 | Single overlay with four copies per frame |
| Redraw gating (`shapeDelta`) | E0 | Redraws every frame |
| Event-driven window tracker, extended frame bounds | E0 | 0.55 s poll with `GetWindowRect`: visible lag and a 7 px gap |
| Per-monitor DPI, real corner radius | E0 | Hardcoded 96 and 12 |
| Hit-testing, clicks only on the spider | E0 | Always click-through; clicks also reach the app below |
| Scroll orders over the spider | E0 | Not wired |
| Silk, hammock, prey, toys, traces, laser, visitors, box, rain layers | E0 | State exists, nothing drawn |
| Name tag, thought bubble in screen space | E0 | Tag off, bubble clipped |
| Full-screen and cinema | E0 | |

## Behavior and physics

| Feature | Level | Notes |
|---|---|---|
| Walk, gait, legs | E1 | C# from prose; 0.25 slip tolerance |
| Posture table | E1 | |
| Air, jumps, landing | E1 | Rescue, bounces missing |
| Silk, rappel, climb, swing, mantle | E1 | Dangling legs not updated |
| Hammock | E1 | Not drawn, legs not tucked |
| Peek-a-boo | E1 | Renderer ignores `HiddenBy`, `PeekGrip` |
| Brain, repertoire | E1 | Many behaviors never picked |
| Pointer: watch, stroke, whip, fidget, cling | E1 | |
| Prey, wildlife, toys, traces | E1 | Headless only |
| Memory, habits, personality | E1 | |

## Art

| Feature | Level | Notes |
|---|---|---|
| Spider body, faces, coats | E1 | Never diffed |
| Hats | E0 for 13 of 38 | Rest E1 |
| Accessories | E0 for 9 of 30 | Rest E1 |
| Patterns | E0 for 9 of 20 | Rest E1 |
| Weather coats, specks, ball pose | E0 | |
| Creatures, toys | E0 | |
| Habitat items, scenery, weather | E0 | Generic polygons at 30 fps |

## UI

| Screen | Level | Notes |
|---|---|---|
| Tray icon and menus | E1 | |
| Panel, 7 pages | E1 | Never compared |
| Studio, 12 tabs | E1 | Text labels instead of thumbnails |
| My Spiders | E1 | |
| Welcome tour, first entrance | E1 | |
| Chat, bug report | E1 | |
| Habitat window and controls | E1 | |

## Sensing

| Sensor | Level |
|---|---|
| Battery saver, charger, lock/unlock, weather, volume, brightness, banners, music and beat | E0 |

## Later

| Item | Notes |
|---|---|
| New leg system v2 (Studio toggle) | Uncommitted on the Mac. After v1.0.1 parity, once it settles. |
