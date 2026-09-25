# Spider Buddy

A friendly jumping spider that lives on your Mac's screen. It crawls the edges
of your display, leaps between your open windows, walks along the Dock, rappels
from the menu bar on a silk thread, and can be picked up and thrown around.

Native AppKit + Core Graphics. No dependencies, no Xcode project, ~2 MB binary.

## Install

Grab the `.dmg` from the [latest release](https://github.com/Ephemerill/spider-buddy/releases/latest),
open it and drag Spider to Applications. The app is ad-hoc signed, so the
first launch needs the usual step for an unsigned app: right-click Spider →
Open, or allow it under System Settings → Privacy & Security.

That is the only time. **Check for Updates…** in the spider's menu asks GitHub
for the newest release and, if there is one, downloads the `.dmg`, swaps the
new app in over the running one and relaunches — without a quarantine flag,
so Gatekeeper does not ask again. Settings and the design are kept.

## Build & run

```bash
./build.sh          # produces spiders.app — the testing build
open spiders.app    # or: ./run.sh  (rebuild + restart)
tools/release.sh    # the release build, "Spider Buddy.app", in a .dmg
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

- Crouches, aims and leaps head-first with a visible push-off, pitching into
  the arc but never rolling past fifty degrees. (A real jumping spider
  trails a safety line on every leap; this one does not — it looked odd
  here, so it is gone.) Over the last stretch of a leap it turns to meet the surface
  it is going to land on — feet first, flipping right over to land upside
  down under a window — and reaches its legs out for it, so touchdown is the
  end of a movement rather than a snap; a fall or a throw looks ahead for
  whatever it is about to hit and does the same. It lands with a squash,
  takes a beat to get its feet under it, then carries on
- Falls, bounces off screen edges, and fires a rescue line if it drops too far
- Rappels head-down on a dragline from its spinnerets, hangs almost still,
  turning part-way round on the line to show its face and drifting back;
  climbs back up hand over hand, facing up the thread
- Walks a proper alternating-tetrapod gait, driven by distance travelled rather
  than a timer: four legs swing while four stay planted, and planted feet hold
  still on the ledge while the body moves over them, so it never skates. The
  body bobs twice a cycle and the planted legs flex against it.

**What it gets up to**

Everything it does is a *posture* — height off the ledge, nose pitch, crouch,
abdomen wag, eyelids — and springs carry the body between postures, so nothing
ever snaps from one stance to the next. The feet are looked after the same
way across every hand-off: a foot left in the air by whatever came before (a
wave, a greeting, a grip on a line) *steps* down onto the ledge, folding at
the knee as it comes rather than sweeping down as a bar; a foot left mid-
stride when a walk stops takes one small step to its place instead of
sliding there, one leg at a time; a step that would begin with the gait
clock already part-way through its window waits for the next one; and a
turn begun face-on (after a greeting, say) sets off from the front view
rather than snapping to profile first. Landing, the body gathers itself
onto the edge and swings square to it over a few frames. It gets going over
a few steps and stops short, leaning into a start and rocking forward on a
stop. And it walks the way a jumping spider walks — in bursts: a few steps,
a stop to look about, a few more — and a walk is usually *for* something,
so at the end of it it has a look round, checks on you, or peers over the
edge. The repertoire, all picked from at random with weights that shift
with context:

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
- **Nervous hop** — whip the pointer past it (fast, within a hand's width)
  and it gives a small startled hop on the spot, legs tucked for an instant,
  with a little burst of "!!" — and that is all; it does not run. Only the
  pointer whipping right across its body properly startles it
- **Stare** — sits still, turned square on to face you, and just watches,
  eyes following the pointer, blinking now and then
- **Bed on a window** — sleepy, it prefers the top of a window: it walks
  round its own window to the top, or leaps onto one it can reach, settles,
  and drops off with Z's rising out of it, drifting and growing as they go
- **Thoughts** — a thought bubble now and then: a heart, a juicy cricket
  when it is hungry, a rain cloud, sunshine, the moon when it is sleepy, a
  music note, a star, a fly, its hammock — or words, from the packs it has
  been given (see Thoughts in the Studio)
- **Drum** — braced low, it drums on whatever it is standing on with its
  front two legs, the way a jumping spider signals: bursts of quick
  alternating taps, then three slower beats with both legs together and a
  dip of the body on each, abdomen quivering in time, music notes on the
  beat. Playful, energetic spiders drum most; a click sometimes gets a drum
  in reply
- **Greet** — turns right round to face you square on, big eyes on the
  pointer, and raises both front legs up and out beside its head in a V,
  waving them a little. It does this when you rest the pointer near it,
  sometimes when you click it, now and then on its own while you are about
  (affectionate spiders most), and **Behavior ▸ Say Hi** asks for it
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
- **Bring the pointer close** while it is sitting about or ambling and it
  notices: it turns round to face it, eyes on it, head tipped toward it, up
  on its toes and leaning after it; straight overhead, it squares up to you
  and looks up. Busy with something — a hunt, a job, a film, a nap — it does
  not stop for you, and a pointer that just sits there is old news after ten
  or twenty seconds.
- **Fidget the pointer** close by like something alive and it decides you
  are prey: a freeze, a creep along its ledge, the poised wiggle, and it
  springs at the pointer and catches it — then hangs off it by its front legs for a few seconds,
  swinging as you drag it, before it drops away on a line. Shake the
  pointer back and forth to fling it off sooner. Turn the hunt off with
  **Pounce on the Cursor** (it still watches).
- Leave it alone for a while and it grooms, rests, then falls asleep

Clicks pass straight through to whatever is underneath unless the pointer is
actually on the spider.

## Silk

Its silk:

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
  the line along the body. The legs on the line move the way the legs on a
  ledge do, only along the thread: each has its natural spot, in its stance
  the foot holds still in the world and slides through the body's frame as
  the body climbs or descends past it, and in its swing it lets go, lifts
  off the line to its own side — over the legs still holding — and reaches
  on to its next grip a stride ahead, near legs hooking from one side and
  far legs from the other. The line itself ends at the spinnerets, so it
  runs exactly through the grips whichever way up it is. Once it stops it
  lets itself back round to hang.
  Swinging, the same hind legs hold the line above the abdomen and the
  front legs hang loose toward the ground.
- **A line means something.** Dropping onto a thread it decides then and
  there what the thread is for, and works through it: down to a chosen
  height, a while hanging there (a bounce on arrival if it is that sort, the
  odd shift of weight that sets it swaying, a note or a sparkle, a look
  about — and it pays out line to come and see a pointer waiting
  underneath), sometimes a second look further down or back up, and then
  one way off it — hauling back up to whatever it hung from, all the way
  down to the floor, working up a swing, or springing off to something
  near. It does not change its mind every few seconds, and it does not turn
  right round on the line: turning to the other side on a thread is a roll
  of the whole body, and it only does that on purpose — to face up the line
  for a real climb, or in a twirl when it is pleased. A window sliding in
  front of it, a meal or the red dot turning up, or being reeled about by
  hand all cut the plan short, and it picks up a fresh one after.
- **The line is a string, not a rod.** Every thread is a short chain of
  points under gravity, tied to the anchor at one end and the spinnerets at
  the other: it sags when it goes slack, lags and whips when it is fired or
  swung on, bows for a moment when it bounces, and — once let go — drifts
  down from its anchor as it fades.
- **The hammock.** Jumping spiders spin a silk retreat to sleep in. Once it
  has been about for a while it picks a top corner of the screen, walks or
  leaps to it, and spins one — on the real walls, with real silk. It backs
  its abdomen onto the side wall and sticks the first thread down with a
  few dabs of its spinnerets; then it climbs the wall, hops across the
  corner onto the underside of the menu bar, and walks out along it with
  the silk paying out behind it from the wall to its spinnerets, taut,
  until it reaches the far anchor and sticks that end down — and the strand,
  stuck at both ends, sinks from that taut line into its sag over a couple
  of seconds, the way slack silk drapes. Back it goes
  the other way — along the underside, a hop down to the wall, down to the
  first anchor — laying the next strand, and so on, crossing and re-crossing
  the corner until a sling of strands hangs there. Then it steps onto the
  silk itself — the sling is ground to its feet like any ledge, so it
  walks it, feet planting on the strand and stepping — in along the sling
  to the middle, a few steps back and forth over the bed tying the
  cross-ties off, and tests it with a bounce. Going to bed later is the
  same walk in along the silk before it curls up, and getting up is a walk
  out to the wall end before it steps off. It is all ordinary
  walking, jumping and one fastening pose on the surfaces it always uses;
  nothing glides. If something interrupts it (a window over the corner, a
  fall, being picked up) what is spun stays, and it comes back to finish
  it. The result is loose and stringy like its other
  silk: uneven strands that each hang a little slack, loops of silk
  drooping beneath, slack cross-ties, tufts where it is stuck down — and
  the corner itself left open behind it. There are four kinds — a long
  shallow **sling**, a deep **pouch** it sinks right into, a loose
  criss-cross **tangle**, and a wide shallow **cradle** made mostly of
  drooping loops — and every one is a little different. To nap it climbs
  in and curls up: the sling gives under its weight, it lies in the lowest
  of the sag with every leg drawn in tight and the front pair folded over
  its face, and breathes, seen through the silk. Lazier spiders nap there
  more often. **Wipe your pointer across it** to tear it down; a couple of
  good swipes clear it, and a sleeping spider tumbles out startled.
  **Build a Hammock**, **Nap in the Hammock** and **Clear the Hammock** are
  under Behavior, and the hammock (kind and all) survives a restart.

## Peek-a-boo

The spider is drawn above every window, but not above the ones in front of
the *window* it is standing on: whatever of it falls inside such a window
is cut out, so a spider on a window's shelf with another window over part
of it really does go behind that window. That is the game. (The screen's
own rim, the menu bar and the Dock are the glass in front of everything:
there it is never covered, however far a window reaches toward the edge —
a Preview window taller than the screen used to hide it on the floor.) When someone is about and
there is a window edge to hide behind nearby, now and then (playful ones
more often) it creeps up to the edge, slips behind it, waits… and bursts
out at you, front legs thrown up, eyes on the pointer — then back behind
and again, two to four times, finishing with a happy wiggle. **Behavior ▸
Peek-a-boo** asks for a game: if there is no edge to hide behind where it
is, it leaps off to find one first.

## Feeding it

**Feed** in the menu releases a cricket, a worm, or a fruit fly onto the
desktop. Ground creatures drop in onto a ledge some way off — the cricket
sits, twitching its antennae, and hops away when the spider closes in; the
worm inches along, and a little faster when something big is near. The fly
is let go in the air and buzzes about in a jittery random walk, perching on
edges to clean itself and taking off again when the spider gets close.

The spider drops whatever it was doing and hunts: it watches its quarry,
walks round its own window to it or leaps to whichever ledge gets it
nearest, walks in, stalks the last stretch low and slow, and pounces once
it is close and the prey is sitting still — snatching whatever its fangs
pass in the air, or catching a fly that comes within reach. A pounce is
aimed at the prey, not the furniture: it sails past any window edge on the
way and only grabs on once it is at its mark or has flown past it. Stalking
works the way it does in life: a creature notices something big moving fast
nearby at once, but something creeping up slowly not until it is very close
— and a frightened cricket as often freezes as hops.

You can pick the creatures up and move them, the same way as the spider:
drag one somewhere else (or flick it) and it drops onto whatever is below,
and the spider's interest is renewed. Then it settles down over the
meal, holding it under its fangs with the front legs and chewing, and the
catch shrinks away as it is eaten. A good meal leaves it visibly happier
(the grin, the sparkle, the hearts, a wiggle) and well fed for a good
while. Up to four things can be loose at once; anything that loses its
surface (a window closing) falls to whatever is below.

## Windows coming over it

The rim of the screen, the menu bar and the Dock are always its to walk:
the spider draws above every window, so a window overlapping the edge of
the display never blocks the edge, and it simply walks along the rim across
it. A *window's* edge is different — a window in front of it hides it. If
such a window opens on top of the spider, or is dragged over it, it gets out
from under at once — within a poll or two — rather than sitting there as if
perched on the glass. It either fires a line straight up and hauls itself,
double time, to whatever is above (a window's underside, the menu bar, the
top of the screen), or lets go and drops — often shooting a line on the way
down to swing out on; from the floor, where a drop is no use, it always goes
up. It never walks along the covered edge to the open part of it: that edge
is behind the window now. If neither is possible it leaps for the nearest
clear spot. Nor does it ever take hold of a window where another hides it —
no dragline fastened to the covered stretch, and no landing on a window
edge unless all of it is clear of every window in front. The same applies when it is
hanging on a line (it climbs straight up out of the way) or asleep in its
hammock (it bails out). "Covered" means either its edge is blocked by a
window in front, or its body is: a window that only overlaps the body
counts too.

## The habitat

**Open Habitat** (Play ▸ Places in the menu bar panel) opens a terrarium
for it: a glass tank in a dark frame, with a painted, living scene behind
the glass, a substrate you can see through the front, and furniture to
climb. The tank rises into place over the spider, and the spider shoots a
line up to the lip of the tank's ground, climbs it hand over hand, and
hops over onto the ground inside. (Up on a window or a wall, it drops down
first; off to one side, it walks over; in its hammock, it gets up; thrown
over the tank, it just drops in.)

Inside, it lives in the tank: it walks along the ground, up and over the
logs and stones standing on it, onto branches, vines and the leaves of the
plant, and up the glass — and it never leaves by itself. It is drawn *in*
the tank, among its furniture, so foliage placed in front hides it as it
walks behind, and other windows cover it like anything else in a window.
Everything it does on the desktop it does in there — hunting what you let
loose with **Feed**, drumming, napping, greeting you — and you can click
it, scroll it on a line, pick it up and throw it just the same. Picked up,
it is in your hand, drawn over everything; carried out through the glass
and let go, it is out on the desktop, and after a while it climbs back in
the same way. Carried over the tank and let go, it is in. Click the glass
and it rings. Drag the tank about and it comes along.

**Let Out** (or the window's close button) closes the tank: the spider
drops from exactly where it was — off the log, the branch, the glass —
onto whatever is below on the desktop, as the tank fades away. The app
remembers which side of the glass it was on across a restart. Desktop-only
things — the hammock, the box, cinema manners, the laser, visitors — wait
for it outside (a box you have drawn is set aside while the tank is open).

The scenery moves, all of it by Core Animation, so it costs the app next
to nothing and stops altogether while the tank is hidden: clouds drift,
light shafts breathe, leaves fall, mist rolls, butterflies wander, the sea
rolls and sparkles with gulls and a sailboat on it, sand blows and a
tumbleweed goes by, crystals glow and water drips in the cave, snow falls
under the northern lights, stars twinkle and fireflies blink by moonlight.
Plants sway, crystals and mushrooms glow, water dishes ripple.

**Decorate** opens a panel beside the tank (the tank itself does not move):
- **Scenery**: Forest, Jungle, Desert, Meadow, Cave, Beach, Snowfall and
  Moonlit, each a picture tile. The furniture takes on the light of the
  place — bluer by moonlight, dimmer in the cave.
- **Add**: perches it can climb (log, branch, driftwood, cork bark, hollow
  log, rock, boulder, bamboo, cactus, leafy plant, hanging vine, water
  dish) and plants and details (fern, tall grass, flowers, succulent,
  mushrooms, moss, leaf litter, pebbles, twigs, crystals). Click one and it
  drops into the most open spot.
- **Layouts**: eight ready-made tanks and a bare one, **Surprise Me** and
  **Clear All**.
- In the tank: click a piece to select it, drag to move it (rocks, pots and
  the like stay on the ground; branches, logs and small things can be
  propped up off it; vines hang from the lid), drag a corner handle to
  resize it. The inspector sizes, flips, duplicates and removes it, and
  puts plants and details **In Front** of the spider or **Behind** it
  (perches are always behind — it climbs them). Keys: ⌫ remove, ⌘D
  duplicate, F flip, arrows nudge (⇧ for more), ⌘Z / ⇧⌘Z undo and redo,
  Esc deselect, then leave.

The habitat is saved as you go. The tank keeps its shape as the window is
resized, and remembers its size.

## Your Mac

Under **Your Mac** in the menu bar panel:
- **Feel the Battery**: in Low Power Mode it gets sleepy and slow, and
  draws fewer frames itself. Plugging in the charger perks it right up.
- **Notice the Weather**: when it rains where you are, rain is on its mind
  (checked every twenty minutes from Open-Meteo, going by roughly where
  your internet connection is). **Rain on the Screen** adds faint streaks
  across the desktop while it rains.
- **Notice Pop-ups**: a notification sliding in makes it jump — right up
  in the air if it is standing on top of something, a start where it
  clings if it is on a side or underneath — and then it stares up at the
  banner for a moment. Turn the volume or brightness up or down and it
  only looks up to see. What a notification says is never read: it only
  sees that a banner came up.

Under **Visitors**, now and then another spider can drop by to play, then
head off again.

## Keeping it in a box

**Behavior ▸ Keep *name* in a Box…** dims the desktop and lets you drag out
a rectangle (Escape cancels). That box is its patch. It is not a cage: a
throw, a fall or a walk along an edge can take it outside — but the moment
it finds itself out, getting back in is the first thing on its mind. It
walks round its own window to the nearest stretch inside (whichever way
round is open and shorter), or leaps to the nearest spot inside it can
reach, or leaps to whatever gets it nearer and tries again; out for a very
long while, it is fetched. Inside, it climbs whatever windows and screen
edges fall within the box exactly as usual, turns back at the box's edge
rather than leaping off, leaps only to spots inside, and prey is released
inside. A box with nothing in it to stand on is different: it makes its
way to it and hangs in from the top on a line, swaying lightly the way a
draught would move it, shifting its height now and then, the odd little
bounce — never a real swing.

Boxed at all, it takes things easy: it decides things about half as often,
rests and looks about far more, dashes about far less, and gives up
swinging on lines and hammock trips altogether. The box shows as a faint
dashed outline and survives a restart; **Redraw the Box…** and **Free
*name* from the Box** sit alongside while it is set. Freed, it carries on
from wherever it is and wanders off in its own time.

## Full-screen video

When any app takes a whole display — a film, most likely — the spider has
cinema manners. On that display only the floor and the ceiling of the
screen exist to walk on: no walls, no menu bar, no Dock, and no windows,
none of which are visible under a full-screen video (so it can no longer
end up walking on thin air where a hidden window used to be, or with only
its legs showing at the edge). It walks to the nearest corner of the
floor and lies down there, facing the picture with its head tipped right
up at it (on the ceiling it hangs as usual in the corner, head turned to
the picture), gaze drifting with whatever is happening on it; now and then
it stretches its legs a short way, grooms, or glances your way; it does not leap,
swing, spin silk, hunt or go to its hammock, it ignores the pointer, and
only after a very long while might it nod off. When the video ends it
carries on as before. (A window is counted as full screen when it covers
the display, or all but the strip a notch takes.)

## Thoughts and words

The **Thoughts** tab in the Studio picks what it may say in a thought
bubble: **Chit-chat** (hi!, boo!, tap tap…), **Encouragement** (drink some
water, take a little break…), **Spider facts** (I have eight eyes…), and
**Bible verses** (short verses with their references, in the King James
wording). Tick any mix, and add your own lines underneath, one per line —
they go into the same hat. **Think something now** tries one in the
preview. Long lines wrap into a bigger bubble.

## Laser pointer

**Behavior ▸ Laser Pointer** turns the pointer into a laser: click
anywhere and a red dot appears there; hold and drag and it moves. The
spider drops whatever it is doing and races for it — along its own edge at
a scurry, or with a leap to whatever is nearest the dot — and when it gets
there it pounces and pats at it; when the dot goes out (a couple of seconds
after you let go) it looks about for it, puzzled. Clicks on the spider or
a creature still pick them up as usual.

## Spider Studio

**Spider Studio…** in the menu (⌘,) opens a Mii-maker-style editor. The left
side is a little terrarium with your spider living in it — it walks the walls,
leaps to the ledge, and you can click, drag and throw it — and every change on
the right shows up there and on your desktop immediately. Nothing is
"applied"; it just is.

| Tab | Options |
|---|---|
| Body | 11 shapes (Classic … Chonk, Tall, Pear, Big Head, Bean, Petite), 3 fuzz levels, size |
| Face | 13 eye styles (Huge, Beady, Sleepy, Sparkly, Cross-eyed, Wink, Glowing, Dizzy, Heart Eyes, Button…), 10 brows, 11 mouths (fangs, tusks, the emerald chelicerae of a bold jumper, a smile, a blep, a grin, buck teeth…), and whether the face is drawn in front of the front legs or behind them |
| Hats | 38 hats — top hat, party hat, crown, beanie, flower, bow, cap, halo, wizard, propeller (it spins as it walks), cowboy, chef, bucket hat, viking, tiara, pirate, mushroom, sombrero, fez, beret, bowler, santa, mortarboard, bunny ears, cat ears, antlers, hard hat, sailor, jester, horns, unicorn, ushanka, pumpkin, strawberry, sweatband, flower crown, a little bird |
| Extras | 30 things to wear — glasses, monocle, shades, heart shades, goggles, eyepatch, a hero mask, a clown nose, moustache, beard, bow tie, necktie, scarf, bandana, bell collar, pearls, a medal, flower lei, headphones, sweater, tutu, backpack, satchel, bindle, jetpack (it fires in the air), balloon, cape, fairy wings, bat wings |
| Legs | 13 styles — slender, chunky, stubby, long, spindly, fuzzy, knobbly, robot, banded, striped, socks, boots — which change the rig, so the walk, turn and jump all adapt |
| Colours | 30 flat coats, 16 gradient coats, 15 *living* coats that move — Rainbow sliding along it, Hot Lava with glowing cracks between drifting crust, Camouflage that takes on the colour of whatever is behind it, Galaxy with twinkling stars, Ocean, Aurora, Disco, Fire, Frost, Toxic, Pearl, Candy Cane, Thunderstorm with lightning, Chrome, Web-Slinger (red and blue, webbed all over, with the emblem on its back) — plus your own: pick any body and leg colour, or blend two or three of your own colours in any direction, shimmering if you like |
| Markings | 20 markings on the abdomen (stripe, spots, chevron, heart, star, skull, moon, flower, eyespots, hourglass, tiger, leopard, checker, lightning…), 20 accent colours or one of your own, or camouflage markings that take on the colour behind it along with a Camouflage coat |
| Personality | a temperament preset (Friendly, Shy, Hyper, Lazy, Curious, Show-off, Chill, Grumpy) or six sliders — energy, curiosity, bravery, playfulness, affection, laziness |
| Gait | walking style (steady, bouncy, tiptoe, lumbering, scurrying), pace, stride, bounce, stance |
| Habits | a dial for each thing it does on its own — wandering, leaping, dropping on a thread, swinging, building and napping in a hammock, nodding off, drumming, dancing, rolling, spinning, push-ups, stretching, wiggling, arms up, looking about, resting, grooming, fidgeting, scratching, peering, thinking, coming to see the pointer, craning at it, staring, glancing, greeting, waving, peek-a-boo. All the way down it never does that; in the middle, as often as it usually would; all the way up, every chance it gets |

Every part is drawn in the body's own frame, so hats stay on through
corners, rolls and hanging upside down, and markings turn with the abdomen.
A gradient or living coat is a colour field over the body: the body is
filled with it, and each leg segment is painted the colour it passes
through, so a rainbow spider's legs are each a different colour. Living
coats are redrawn steadily even while it stands still. Camouflage goes by
what it is standing on — the window colour for the current appearance on a
window, the wallpaper's average colour on the edge of the screen — and, if
you let it see the screen (Screen Recording, from the button in the
Studio), by the actual pixels behind it; either way it drifts toward the
new colour rather than snapping, so you can watch it change as it steps
from a window onto the desktop. Every shade of it — blotches, legs, and the
outline, always a touch darker than the body — is a fixed step from that
colour, so nothing flips from darker to lighter as the colour behind it
drifts.
The personality sliders weight its decisions rather than switch things off: a
shy spider still waves sometimes, a grumpy one occasionally turns its back on
you when poked, a brave one stands its ground when you swipe at it. The habit
dials are the switches: they sit on top of the personality, and the ends of
each one really are never and always.

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
| Open Habitat / Close Habitat | the terrarium; see The habitat |
| Behavior ▸ | everything it can be asked to do: Say Hi, Toss It, Swing!, Feed ▸, the hammock, and the box |
| Behavior ▸ Build a Hammock / Nap in the Hammock / Clear the Hammock | see Silk |
| Size | Tiny → Chonky |
| Energy | Sleepy → Caffeinated (the same slider as the studio's) |
| Follow the Cursor | whether it cares where your pointer is |
| Pounce on the Cursor | whether a pointer that fidgets close by gets stalked and caught (it still watches it either way) |
| Shoot Webs | whether it rappels, swings, drops on a dragline and catches a fall on a line |
| Build Hammocks | whether it spins a hammock in a corner on its own (also gates Behavior ▸ Build a Hammock) |
| Click to Pick Up | turn off to make it fully click-through |
| Pause | freeze it |
| Launch at Login | |
| Check for Updates… | asks GitHub for a newer release; installs it over this copy and relaunches (see Install) |
| Bring *name* to the Middle | lost it? puts it in the air in the middle of the main screen, letting go of everything (line, hammock, pointer, meal), and it falls from there onto whatever is below |
| Reset Everything | starts over: the app relaunches itself, rebuilding every window and re-reading the desktop. The design, settings and hammock are kept — they are saved |

## Permissions

None. Window geometry comes from `CGWindowListCopyWindowInfo`, which needs no
entitlement — window *titles* and screen contents would, and are never read. Notification
banners are noticed the same way, by their windows alone; the volume comes
from Core Audio, and the brightness of a built-in display from
DisplayServices.

## Code map

| File | |
|---|---|
| `Math.swift` | vectors, springs, easing, smooth noise |
| `Surfaces.swift` | turns screens/windows/Dock/menu bar into walkable loops |
| `Habitat.swift` | the tank's model: biomes, furniture, layouts, and the surfaces the spider walks on in there |
| `HabitatArt.swift` | painting the tank: palettes, sky, scenery, substrate, glass, and the pictures the moving parts are made of |
| `HabitatItems.swift` | painting the furniture, and the picker's thumbnails |
| `HabitatAtmosphere.swift` | what moves in the tank's air, per biome, as Core Animation layers and emitters |
| `HabitatScene.swift` | the inside of the tank: its layers, the spider and creatures drawn in it, the mouse, decorating |
| `HabitatWindow.swift` | the tank's window: frame, toolbar buttons, the decorating panel, undo |
| `Prey.swift` | the creatures: their behaviour, drawing, and the click-through window they live in |
| `WindowTracker.swift` | polls window rectangles — 30 Hz while any window is moving, 10 Hz when the desktop is still — and spots notification banners coming up |
| `SystemSense.swift` | the Mac it lives on: Low Power Mode, the charger, the weather, the volume and the brightness |
| `Visitors.swift` | spiders from elsewhere dropping by to play |
| `Panel.swift` | the menu bar panel: its pages, switches, sliders and buttons |
| `Spider.swift` | state machine, physics, gait, decisions |
| `SpiderRenderer.swift` | all the drawing, in body-local coordinates, parametrised by the look |
| `SpiderDesign.swift` | every part, colourway, personality and gait option; the saved design |
| `Skin.swift` | how the coat is painted: flat, gradient, custom and living coats, and the palette the renderer draws with |
| `Studio.swift` | the studio window, option grids, thumbnails and the terrarium preview |
| `OverlayWindow.swift` | transparent always-on-top panel, silk layers, input |
| `AppDelegate.swift` | menu bar item, display link, settings |
| `Updater.swift` | Check for Updates: GitHub Releases lookup, `.dmg` download, swap-in, relaunch |

### Releasing

```bash
echo 0.6.0 > VERSION          # bump; the tag will be v0.6.0
tools/release.sh --publish    # build, package build/SpiderBuddy-0.6.0.dmg, create the GitHub release
```

`build.sh` stamps `VERSION` into the app's `Info.plist`; the updater compares
that against the newest release's tag, so the tag must be `v` + `VERSION`.
Publishing needs the `gh` CLI (`brew install gh`), logged in or with
`GH_TOKEN` set.

### Tools

| | |
|---|---|
| `./tools/preview.sh` | renders a contact sheet of every pose to `build/preview.png` — the fastest way to judge a drawing change. `--single` renders one big. |
| `./build/Preview x --cliptest` | measures how far the furthest drawn pixel actually is from the body centre, across every pose and angle, and checks `SpiderRenderer.drawRadius` covers it. The sprite is re-rasterised every frame, so its size is a direct CPU cost — run this after any change to the art or to the splay/stretch extremes |
| `./tools/film.sh` | filmstrip of the real walk cycle along each screen edge, with the edge drawn in, plus a standoff-drift readout |
| `./tools/film.sh out.png --cycle` | one full gait cycle at 2×, for judging the walk itself |
| `./tools/film.sh out.png --desk` | the spider at actual size on a mock desktop, on every kind of edge — the most useful single view |
| `./tools/film.sh out.png --peekaboo` | the peek-a-boo game as a strip of moments, window drawn over it |
| `./tools/film.sh out.png --hunt cricket\|worm\|fly` | releases prey on a mock desktop and films the chase, with close-ups of the pounce and the meal |
| `./tools/film.sh out.png --jump [--under]` | a real leap drawn along its own trajectory — onto a window's side, or up onto its underside |
| `./tools/film.sh out.png --hang` | descending, hanging and climbing a dragline |
| `./tools/film.sh out.png --swing [--floor \| --fromhang]` | a swing on a line, onion-skinned, from a window top, the floor, or worked up from a hang; prints where each pass reverses |
| `./tools/film.sh out.png --hammock` | the hammock being spun in a corner, panel by panel, and slept in |
| `./tools/film.sh out.png --strip corner` | walks it round a window corner, onion-skinned in world space |
| `./tools/film.sh out.png --strip turn` / `--strip peek` / any activity name (`watch` included) | filmstrip of that animation |
| `./tools/film.sh x --seq walk:2,look,greet:1.6,turn` | runs activities back to back (`:seconds` optional) and lays out every 4th frame in a grid — `build/seq.png` — for looking at one hand-off frame by frame. `SEQ_EVERY=1` for every frame, `SEQ_TRACE=1` to print foot positions |
| `./tools/jerk.sh [seconds] [runs]` | the jerk detector: runs the spider headless and flags every frame where the body, the heading or a foot (relative to the body) moves further than a frame's worth should, grouped by what it was doing on either side. Anything over about two flags a minute is worth a look; `JERK_VERBOSE=1` prints each one with the frames leading up to it |
| `./tools/sim.sh` | runs the spider headless against a synthetic desktop for four simulated minutes, then a scripted pass over grab / throw / rappel / window-closes-underneath / petting, swing / hammock build / nap / wipe-away, then every temperament preset for 150 s each |
| `./tools/gallery.sh` | every studio option thumbnailed the way the studio shows it, plus random designs mid-walk — `build/studio.png` |
| `SPIDER_STUDIO_SHOT=dir ./spiders.app/Contents/MacOS/DesktopSpider` | writes a PNG of each studio tab to `dir` and quits |
| `./tools/bench.sh` | times one rendered frame |
| `SPIDER_STATS=1 ./spiders.app/Contents/MacOS/DesktopSpider` | prints fps and a per-frame budget once a second |

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
- **The top of the screen is not a surface.** The very top edge of a display
  is under the menu bar, where the spider cannot be seen; it used to walk
  along it and vanish, and a throw could leave it lost up there. On a display
  with a menu bar the border is now a U — down one wall, along the floor, up
  the other — with the walls stopping short of the menu bar, under whose lip
  it hangs instead. (Under a full-screen video there is no menu bar, and the
  ceiling is a surface again.)
- **A hammock that is not being built does not exist.** Planning a hammock
  used to stake out the corner at once, and if the trip there was called off
  (a full-screen video, a long detour) the two anchor tufts stayed in the
  corner for ever with nothing to build. Now nothing is drawn until the first
  strand is laid, an unfinished hammock nobody is working on fades away on
  its own, a half-made one goes with a single wipe of the pointer, and the
  menu offers **Clear the Hammock** whenever there is any silk there at all.
- **A line hung near a screen edge could pin it dead still — or jitter.**
  The sideways snag that keeps a swing on the display reversed the angular
  velocity whenever the body was inside the edge margin. A line whose
  anchor was itself in that margin has the bottom of its swing "outside"
  already, so the snag fired at the bottom of every pass — at first pinning
  it dead still, and after the first fix (snag only when heading further
  out) shaking it back and forth at the bottom of the line every frame. The
  snag now applies only to lines hung from well inside the screen; one at
  the very edge is simply left to hang a little off it. The widest-swing
  limit is likewise a gentle push back rather than a bounce.
- **It no longer tumbles at the ends of a swing.** It used to turn to face
  the way it was going on every pass, and on a line that turn is a
  half-roll of the whole body — so each end of the arc was a somersault.
  Now it keeps the same side to you for the whole swing and simply hangs
  along the thread, the body trailing the line a little as it goes.
- **Turning round on a hang no longer jumps it sideways.** When it twists
  to show its other side, the spinnerets swap sides in sprite space at
  the instant it passes the front view, while the body takes a moment to
  come round. Taken literally that moved the body the width of its abdomen
  in one frame and wobbled it back. The body's offset from the point it
  holds on the line now eases over, and the thread, pinned to the real
  spinnerets, bends a touch until it has.
- **A low window is a step down, not a jump.** Hanging under a window that
  sits just above the floor, the spider's body is at almost the same height
  as it would be standing on the floor, so no jump target ever qualified
  (the search wanted a spot at least 70 px away) and every leap it did pick
  would have fired straight into the window it was hanging from. Now
  anything below counts as a drop, however short; a launch that points into
  the surface it is on becomes a let-go-and-fall with a push away from it;
  and from any underside it as often as not simply lets go.
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
