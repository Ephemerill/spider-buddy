# Desktop Spider

A friendly jumping spider that lives on your Mac's screen. It crawls the edges
of your display, leaps between your open windows, walks along the Dock, rappels
from the menu bar on a silk thread, and can be picked up and thrown around.

Native AppKit + Core Graphics. No dependencies, no Xcode project, ~2 MB binary.

## Build & run

```bash
./build.sh          # produces Spider.app
open Spider.app     # or: ./run.sh  (rebuild + restart)
```

`build.sh` compiles with Xcode's toolchain when it is installed. It has to:
the bare Command Line Tools ship an SDK whose Swift build does not match their
own compiler, so every build there recompiles the system module interfaces —
about two minutes each time, and on this machine it eventually fails outright.
With Xcode's toolchain a full build is a couple of seconds.

It appears as a small spider in the menu bar — there is no Dock icon and no
window. Quit from that menu.

## What it does

**Places it can walk**
- The inside border of every display, all the way around the corners
- The whole perimeter of any open window — standing on the top like a shelf,
  round the corner and down the side, hanging under the bottom — riding along
  when you move or resize the window
- The top of the Dock
- The underside of the menu bar

**How it carries itself**

It is drawn **in profile**, standing on the edge: body above the ledge, legs
reaching down to it, seen from the side. A spider on a shelf drawn from above
reads as crawling across whatever is behind it; drawn from the side it reads
as standing on the shelf. Its feet land on the edge itself — the path stands
off the border by the height of the body — so it perches on the rim and never
covers a window's contents. Turning round is a mirror image animated through
zero width, not a rotation; rounding a corner is a rotation. On a window's side
it clings with its feet on the window; under the menu bar it hangs upside down.

- Crouches, aims and leaps head-first with a visible push-off, trailing a silk
  dragline like the real animal, pitching into the arc but never rolling past
  fifty degrees. Over the last stretch of a leap it turns to meet the surface
  it is going to land on — feet first, flipping right over to land upside
  down under a window — and reaches its legs out for it, so touchdown is the
  end of a movement rather than a snap; a fall or a throw looks ahead for
  whatever it is about to hit and does the same. It lands with a squash,
  takes a beat to get its feet under it, then carries on
- Falls, bounces off screen edges, and fires a rescue line if it drops too far
- Rappels head-down on a dragline from its spinnerets, hangs almost still,
  twisting slowly on the line and showing its face as it comes round; climbs
  back up hand over hand, facing up the thread
- Walks a proper alternating-tetrapod gait, driven by distance travelled rather
  than a timer: four legs swing while four stay planted, and planted feet hold
  still on the ledge while the body moves over them, so it never skates. The
  body bobs twice a cycle and the planted legs flex against it.

**What it gets up to**

Everything it does is a *posture* — height off the ledge, nose pitch, crouch,
abdomen wag, eyelids — and springs carry the body between postures, so nothing
ever snaps from one stance to the next. The repertoire, all picked from at
random with weights that shift with context:

- **Walk**, with a speed, stride and bob picked fresh for every bout and one
  of four gaits — plain, bouncy, on tiptoe, or a lumbering trudge — plus a
  slow drift in pace within the bout; **sneak** (low and slow); **scurry** (a
  burst)
- **Glance** — every few seconds it turns three-quarters toward you for a
  look, even mid-stride, and carries on
- **Turn round** — a real turn on the spot: the profile swings through a
  front view (the pose of the reference art) and out the other side, and the
  feet *step* round in the usual tetrapod waves; a **spin** is two of those
  back to back
- **Round a corner** — the path is rounded so the body swings round, and every
  foot is placed on the *actual* edge, so the feet wrap onto the next side
- **Wave** — big sweeps from the shoulder, leaning back; **arms up** — both
  front legs thrown high, as a greeting or a threat display
- **Roll** — gathers itself with its feet planted, rocking back, then tucks
  into a ball and rolls a full turn along the ledge: the ball sits on the
  ledge and turns exactly with the ground it covers, so it never slides, and
  it comes out of it with a squash before the feet come back down
- **Dance** — bounces side to side with the abdomen going and the front legs
  pumping, to music notes
- **Peek** over the end of a ledge nose-down; **peer** nose-down at the ledge
  itself, then look up. Every lean like this is a lean of the *body*, about
  the hips: the planted feet stay where they are on the ledge and the legs
  flex under it, the way a real spider shifts its weight — only a foot
  already in the air goes with the body
- **Crouch and wiggle** before a leap — the abdomen-wiggle tell of a real
  jumping spider
- **Look about** (eyes dart), **rest** (settles low, heavy-lidded), **sleep**,
  then **stretch** up on tiptoe and **shake** itself off on waking
- **Groom** its face, **scratch** its abdomen with a back leg, **fidget** with
  a front foot, stretch one **back leg** out behind it then the other, do a few
  **push-ups**, **wiggle** happily, **bounce**
- **Curious** — front legs come up and feel the air when your pointer hovers
  near, with a "?"
- Standing, it is never quite still — a slow shift of weight, breathing, eyes
  that dart, blinks singly or twice. On a web it hangs head-down, twists
  slowly, and hauls itself up hand over hand.

**Interaction**
- **Click and drag** to pick it up; **flick and release** to throw it with real
  momentum. Throw it hard enough and it will catch itself on a web.
- **Click** it for a wave, arms up, a startle, a curious look, or a glance
- **Double-click** for a bounce-and-wiggle or a dance with arms up
- **Scroll** over it while it's dangling to raise and lower it on its thread
- **Stroke it** — move the pointer back and forth over it and it squints,
  blushes, wiggles and puffs hearts
- **Right-click** it for the menu
- Swipe the cursor at it fast and it gets startled and scurries away
- Leave it alone for a while and it grooms, rests, then falls asleep

Clicks pass straight through to whatever is underneath unless the pointer is
actually on the spider.

## Silk

Beyond the dragline it already trails on every leap:

- **Swinging.** From a ledge it picks something up ahead — a window corner,
  the menu bar, the screen top — rears up, fires a line at it (one leg
  pointing the way), pushes off and swings on it, reeling in to gather
  speed. Nothing comes from nowhere: if the push-off did not make a big
  enough arc, or it starts from a plain hang, it pumps the swing up pass by
  pass — kicking its legs and shifting its weight in time with the motion —
  until the arc is as big as it wants. Then it lets go near the top of a
  swing and flies, or grabs whatever it swings past. Swinging, it hangs the
  way a weight on a string does: in line with the thread, head to the
  ground, tilting with the line at the ends of the arc and trailing it a
  little through each pass. A rescue line caught at speed turns into a
  swing too, so a bad leap can chain into another. **Swing!** is in the
  menu.
- **Hanging.** On a dragline it hangs head down, the way a spider does,
  hind legs hooked round the thread above its abdomen — the near legs from
  one side, the far legs from the other, so the line runs between them —
  and front legs folded in; descending, it pays out line through those hind
  feet. To climb it rolls head-up and hauls itself up hand over hand with
  all eight legs: the front pairs grip above the head, the hind pairs work
  the loose silk trailing from the spinnerets, and every foot holds still on
  the thread while the body moves past it, opening off the line only to
  reach on again. Once it stops it lets itself back round to hang.
  Swinging, the same hind legs hold the line above the abdomen and the
  front legs hang loose toward the ground. It also bounces on the line,
  twirls, kicks itself swinging, and pays out line to come and look at a
  pointer waiting underneath.
- **The line is a string, not a rod.** Every thread is a short chain of
  points under gravity, tied to the anchor at one end and the spinnerets at
  the other: it sags when it goes slack, lags and whips when it is fired or
  swung on, bows for a moment when it bounces, and — once let go — drifts
  down from its anchor as it fades.
- **The hammock.** Jumping spiders spin a silk retreat to sleep in. Once it
  has been about for a while it picks a top corner of the screen, walks or
  leaps to it, and spends a few seconds going back and forth across the
  corner laying strands: a sling strung from the wall to the underside of
  the menu bar, sagging like a hammock, with the corner itself left open
  behind it. Afterwards it lies in the sag and naps there now and then
  (lazier spiders more often), seen through the silk. **Wipe your pointer
  across it** to tear it down; a couple of good swipes clear it, and a
  sleeping spider tumbles out startled. **Build a Hammock**, **Nap in the
  Hammock** and **Clear the Hammock** are in the menu, and the hammock
  survives a restart.

## Windows coming over it

If a window opens on top of the spider, or is dragged over it, it gets out
from under at once — within a poll or two — rather than sitting there as if
perched on the glass. It either fires a line straight up and hauls itself,
double time, to whatever is above (a window's underside, the menu bar, the
top of the screen), or simply lets go and drops to whatever is below; from
the floor, where a drop is no use, it always goes up. If neither is
possible it leaps for the nearest clear spot. The same applies when it is
hanging on a line (it climbs straight up out of the way) or asleep in its
hammock (it bails out). "Covered" means either its edge is blocked by a
window in front, or its body is: a window that only overlaps the body
counts too.

## Full-screen apps

When any app takes the whole display the spider gets out of the way: it
goes to sleep in its hammock if it has one, otherwise it walks to one of
the bottom corners and sleeps there, ignoring the pointer, until the app
leaves full screen. (The full-screen window itself is never treated as
furniture to climb on.)

## Spider Studio

**Spider Studio…** in the menu (⌘,) opens a Mii-maker-style editor. The left
side is a little terrarium with your spider living in it — it walks the walls,
leaps to the ledge, and you can click, drag and throw it — and every change on
the right shows up there and on your desktop immediately. Nothing is
"applied"; it just is.

| Tab | Options |
|---|---|
| Body | 7 shapes (Classic … Chonk, Tall), 3 fuzz levels, size |
| Face | 8 eye styles (Huge, Beady, Sleepy, Sparkly, Cross-eyed…), 7 brows, 6 mouths (fangs, tusks, the emerald chelicerae of a bold jumper, a smile) |
| Legs | 8 styles — slender, chunky, stubby, long, fuzzy, banded, socks — which change the rig, so the walk, turn and jump all adapt |
| Colours | 14 coats, 9 markings on the abdomen, 10 accent colours |
| Hats | top hat, party hat, crown, beanie, flower, bow, cap, halo, wizard, propeller (it spins as it walks) |
| Extras | glasses, shades, monocle, bow tie, scarf, headphones, bandana, backpack |
| Personality | a temperament preset (Friendly, Shy, Hyper, Lazy, Curious, Show-off, Chill, Grumpy) or six sliders — energy, curiosity, bravery, playfulness, affection, laziness |
| Gait | walking style (steady, bouncy, tiptoe, lumbering, scurrying), pace, stride, bounce, stance, how keen it is to leap between windows and to drop on silk |

Every part is drawn in the body's own frame, so hats stay on through
corners, rolls and hanging upside down, and markings turn with the abdomen.
The personality sliders weight its decisions rather than switch things off: a
shy spider still waves sometimes, a grumpy one occasionally turns its back on
you when poked, a brave one stands its ground when you swipe at it.

Give it a **name** and it tells you: rest the pointer on it for a moment and a
name tag appears. The dice picks one for you; **Surprise Me** rolls a whole
new spider.

The design is saved as JSON in the app's defaults.

## Menu

| Item | |
|---|---|
| Hide *name* / Show *name* | toggle it off and on (the icon dims while hidden) |
| Spider Studio… | customise it (see above) |
| Come Here | it walks or jumps to your pointer |
| Say Hi / Toss It / Swing! | |
| Build a Hammock / Nap in the Hammock / Clear the Hammock | see Silk |
| Size | Tiny → Chonky |
| Energy | Sleepy → Caffeinated (the same slider as the studio's) |
| Follow the Cursor | whether it cares where your pointer is |
| Spin Webs | disable silk entirely |
| Click to Pick Up | turn off to make it fully click-through |
| Pause | freeze it |
| Launch at Login | |

## Permissions

None. Window geometry comes from `CGWindowListCopyWindowInfo`, which needs no
entitlement — window *titles* and screen contents would, and are never read.

## Code map

| File | |
|---|---|
| `Math.swift` | vectors, springs, easing, smooth noise |
| `Surfaces.swift` | turns screens/windows/Dock/menu bar into walkable loops |
| `WindowTracker.swift` | polls window rectangles — 30 Hz while any window is moving, 10 Hz when the desktop is still |
| `Spider.swift` | state machine, physics, gait, decisions |
| `SpiderRenderer.swift` | all the drawing, in body-local coordinates, parametrised by the look |
| `SpiderDesign.swift` | every part, colourway, personality and gait option; the saved design |
| `Studio.swift` | the studio window, option grids, thumbnails and the terrarium preview |
| `OverlayWindow.swift` | transparent always-on-top panel, silk layers, input |
| `AppDelegate.swift` | menu bar item, display link, settings |

### Tools

| | |
|---|---|
| `./tools/preview.sh` | renders a contact sheet of every pose to `build/preview.png` — the fastest way to judge a drawing change. `--single` renders one big. |
| `./build/Preview x --cliptest` | measures how far the furthest drawn pixel actually is from the body centre, across every pose and angle, and checks `SpiderRenderer.drawRadius` covers it. The sprite is re-rasterised every frame, so its size is a direct CPU cost — run this after any change to the art or to the splay/stretch extremes |
| `./tools/film.sh` | filmstrip of the real walk cycle along each screen edge, with the edge drawn in, plus a standoff-drift readout |
| `./tools/film.sh out.png --cycle` | one full gait cycle at 2×, for judging the walk itself |
| `./tools/film.sh out.png --desk` | the spider at actual size on a mock desktop, on every kind of edge — the most useful single view |
| `./tools/film.sh out.png --jump [--under]` | a real leap drawn along its own trajectory — onto a window's side, or up onto its underside |
| `./tools/film.sh out.png --hang` | descending, hanging and climbing a dragline |
| `./tools/film.sh out.png --swing [--floor \| --fromhang]` | a swing on a line, onion-skinned, from a window top, the floor, or worked up from a hang; prints where each pass reverses |
| `./tools/film.sh out.png --hammock` | the hammock being spun in a corner, panel by panel, and slept in |
| `./tools/film.sh out.png --strip corner` | walks it round a window corner, onion-skinned in world space |
| `./tools/film.sh out.png --strip turn` / `--strip peek` / any activity name | filmstrip of that animation |
| `./tools/sim.sh` | runs the spider headless against a synthetic desktop for four simulated minutes, then a scripted pass over grab / throw / rappel / window-closes-underneath / petting, swing / hammock build / nap / wipe-away, then every temperament preset for 150 s each |
| `./tools/gallery.sh` | every studio option thumbnailed the way the studio shows it, plus random designs mid-walk — `build/studio.png` |
| `SPIDER_STUDIO_SHOT=dir ./Spider.app/Contents/MacOS/DesktopSpider` | writes a PNG of each studio tab to `dir` and quits |
| `./tools/bench.sh` | times one rendered frame |
| `SPIDER_STATS=1 ./Spider.app/Contents/MacOS/DesktopSpider` | prints fps and a per-frame budget once a second |

## Performance

Roughly 15% of one core while it is up and about, ~4% resting, 12 MB
resident. Every visible change redraws the sprite — the earlier, cheaper
threshold was quietly dropping frames while it walked. Three things get it there, and all three are easy to undo by
accident:

- **The window is small and follows the spider.** A screen-sized transparent
  overlay has to be recomposited every frame — that alone was most of an
  earlier 26%. Silk needs to reach across the desktop, so it lives in a
  separate screen-sized window that is ordered out whenever no thread is out.
- **The layer is only re-rasterised when the spider's *shape* changes.**
  Position is just `layer.position`, which is free. A spider standing still or
  asleep redraws almost never.
- **The display link is asked for 60 Hz outright** (`preferredFrameRateRange`),
  and skips two frames in three when the picture has not changed for a
  second. Gating a 120 Hz link by elapsed time instead gave alternating 16 ms
  and 25 ms steps, which read as stutter in everything that moved.

## Notes

- If your Dock is set to auto-hide, there is nothing there to walk on most of
  the time; the spider will use it during the moment it slides into view. Turn
  auto-hide off to get a Dock it can properly patrol.
- It draws above the menu bar and the Dock but below open menus, so it can hang
  in front of the clock without ever swallowing a menu click.

### Tuning

Almost everything worth playing with is at the top of `Spider.swift`
(`SpiderConfig`, `gravity`, `strideLength`, `swingDuty`, `maxJumpSpeed`), the
pose presets in `Spider.poseTarget`, and the palette, leg rig and metrics at the
top of `SpiderRenderer.swift`.

Two things there are less obvious than they look:

- **`ballistic` checks reachability before it commits.** The obvious version
  picks a flight time, solves for the velocity, then clamps the speed to
  something sane — which quietly breaks the equation it just solved and turns
  every long jump into a fall short of the target. It solves for the
  minimum-energy launch instead and returns nil when a target is genuinely out
  of range, so a jump either looks like a jump or is never attempted.
- **An escape is never restarted while it is under way.** The covered check
  runs every frame; it used to call the escape again each time it fired, and
  since the escape begins with a turn and a crouch that take longer than the
  check's delay, the crouch was restarted forever — a spider under a window
  froze in place. `escapeUntil` holds the check off while an escape is in
  progress.
- **A lean never moves the feet.** `pitch` used to be folded into the sprite's
  heading, which tilted the whole drawing — legs, feet and all — so a peek
  over a ledge lifted the back feet off it. It is now `pose.bodyPitch`: the
  renderer turns the body, face and hat about `leanPivot` (between the hips)
  and the pose moves the hips with it, while a foot on the ground is left
  exactly where the gait put it. The legs are drawn outside that transform.
- **The leg rig is art, not IK — except on a thread.** `SpiderRenderer.knee`
  swings the designed rest shape about the hip rather than solving a two-bone
  chain, because a solver picks a different elbow side as the foot crosses the
  body and the legs stop looking like they belong to one animal. The one place
  a real solver is used is a leg holding the line (`kneeIK`), where the bend
  side is chosen on purpose — outward from the thread — and each foot is
  pulled back along the line to the nearest point that leg can actually reach,
  so nothing strains. The held stretch of line is drawn inside the sprite
  between the far legs and the body, which is what makes the far feet read as
  behind it and the near feet in front. Near-side legs are drawn in front of
  the body, far-side legs behind it and a shade darker, feet staggered so all
  eight show.
- **The turn is a yaw, not a mirror.** `pose.facing` runs from +1 through 0 to
  -1; its sign picks the mirror and its magnitude blends every part of the
  layout between profile and a front view. The front-view leg layout is
  symmetric under leg i ↔ 7-i, so at the exact moment the mirror flips the
  feet are re-paired and nothing jumps.
- **`Seg` fixes its own handedness.** The sprite frame is built from the edge:
  +x along it, +y along its outward normal. `Seg.init` reorders its endpoints
  so the normal is always 90° counter-clockwise of the direction of travel, so
  an edge wired up backwards cannot stand the spider on its head.
