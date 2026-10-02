import AppKit
import CoreGraphics

// MARK: - Configuration

struct SpiderConfig {
    var scale: CGFloat = 1.0
    var walkSpeed: CGFloat = 62          // px/s at scale 1
    var liveliness: CGFloat = 1.0        // how often it decides to do something
    /// Watches the pointer: its eyes, head and body follow it about, and
    /// it turns to look at it.
    var followCursor: Bool = true
    /// Goes over to see the pointer: along its edge to it, or down a line
    /// to one below the window it is on.
    var approachCursor: Bool = true
    /// A pointer that fidgets close by for long enough gets stalked and
    /// pounced on. Off, it only watches.
    var pounceOnCursor: Bool = true
    /// Shooting lines: rappelling, swinging, draglines and catching a fall.
    var webs: Bool = true
    /// Spinning a hammock in a corner to rest in.
    var hammocks: Bool = true
    var paused: Bool = false
}

/// The weather where it is, as it feels it: none at all on the desktop;
/// in the habitat, whatever its sky is doing (see Weather.swift).
struct WeatherFeel: Equatable {
    /// The wind as it blows right now, signed (+ blowing to the right),
    /// gusts and all: about 1 in a gale, up to 2 in a big gust.
    var wind: CGFloat = 0
    /// How gusty it is, 0…1.
    var gust: CGFloat = 0
    /// What is coming down, 0…1 each.
    var rain: CGFloat = 0, snow: CGFloat = 0, hail: CGFloat = 0, sand: CGFloat = 0
    var fog: CGFloat = 0, sun: CGFloat = 0, cold: CGFloat = 0, heat: CGFloat = 0
    var rainbow: CGFloat = 0
    /// Lightning about.
    var storm: CGFloat = 0
    /// The night sky putting on a show: shooting stars, the northern lights.
    var skyShow: CGFloat = 0

    static let calm = WeatherFeel()
    var isCalm: Bool { self == .calm }
    /// Anything coming down on it hard enough to mind.
    var rough: Bool { rain > 0.25 || hail > 0.1 || snow > 0.55 || sand > 0.3 || storm > 0.3 }
}

/// A drop of water dripping off it, a splash of rain on its back, a puff of
/// snow or dust shaken off it, a hailstone glancing off it: drawn round the
/// sprite, in world points relative to the body (`SpiderPose.pos`).
struct Speck {
    enum Kind { case water, snow, sand, hail, ring }
    var p: V2
    var r: CGFloat
    var kind: Kind
    var alpha: CGFloat
    /// Drawn out along its fall (1: round).
    var stretch: CGFloat = 1
}

// MARK: - Pose handed to the renderer (all body-local unless noted)

enum Emote {
    case none, hearts, zzz, surprise, sparkle, question, note
    case exclaim        // a little burst of "!" — a nervous start
    case charge         // crackling with lightning — the charger went in
    case thought        // a thought bubble; what is in it is `SpiderPose.thought`
}

/// What is in a thought bubble.
enum Thought: Equatable {
    case heart, hungry, rain, sun, moon, music, star, bug, home
    case text(String)
    case snow, wind, storm, rainbow
}

struct LegPose {
    var hip: V2
    var knee: V2
    var foot: V2
    var lift: CGFloat
}

struct SpiderPose {
    var pos: V2 = .zero                  // world, the body origin
    /// Rotation of the sprite: its +x (the way it faces) maps to this angle.
    var heading: CGFloat = 0
    /// +1 or -1, animated through 0 when it turns round.
    var facing: CGFloat = 1
    /// Extra rotation about the body, in sprite space: the roll.
    var spin: CGFloat = 0
    /// How far it is balled up, 0..1: the body folded at the waist.
    var ball: CGFloat = 0
    /// 1 when standing on something, 0 in the air. Drives the contact shadow.
    var grounded: CGFloat = 1
    /// World point the silk attaches to (top of the abdomen).
    var silkAttach: V2 = .zero
    var scale: CGFloat = 1
    var stretch: CGFloat = 1             // along the body
    var fatten: CGFloat = 1              // vertical, pivoting on the feet
    var legs: [LegPose] = []
    var look: V2 = .zero                 // screen-space direction of gaze
    var blink: CGFloat = 0
    var happy: CGFloat = 0
    var startled: CGFloat = 0
    var sleep: CGFloat = 0
    var abdomenSway: CGFloat = 0
    var emote: Emote = .none
    /// How far through its time the emote is, 0…1: what fades it in and out.
    var emoteT: CGFloat = 0
    /// Seconds since the emote began, never held back: what the looping
    /// ones (the Z's) animate on, so a long sleep does not slow them down.
    var emoteClock: CGFloat = 0
    var thought: Thought = .heart
    var web: (anchor: V2, alpha: CGFloat, slack: CGFloat)?
    /// The line as a chain of world points, anchor first, when it is live.
    var webPoints: [V2] = []
    /// The stretch of line it is holding, in sprite units, drawn between the
    /// far legs and the body so the legs read as gripping it from both sides.
    /// `tail` is how much of the silk it has hauled in hangs gathered below.
    var thread: (a: V2, b: V2, tail: CGFloat, alpha: CGFloat)?
    /// Where the line comes out of it, when that is not where the held
    /// stretch starts: climbing, the silk runs from the spinnerets to the
    /// line along its belly.
    var threadFrom: V2?
    /// Rolling over on a line, where the silk from the spinnerets comes in
    /// against the belly, to run along it to where the held stretch starts.
    var threadVia: V2?
    var time: CGFloat = 0
    var grabbed: CGFloat = 0
    /// How it is dressed.
    var outfit = SpiderLook()
    /// The colour of whatever is behind it, for a camouflaged coat.
    var surroundings = SpiderPose.defaultSurroundings
    static let defaultSurroundings = RGB(0.94, 0.92, 0.88)
    var name = ""
    /// Opacity of the name tag under it.
    var nameTag: CGFloat = 0
    /// Distance walked, in body units. Drives anything that should turn with travel.
    var odometer: CGFloat = 0
    /// A lean of the body alone — nose up (+) or down (-) about the hips —
    /// with a small shift to go with it. The planted feet stay where they are;
    /// only the hips (and any foot already in the air) move with it.
    var bodyPitch: CGFloat = 0
    var bodyShift: V2 = .zero
    /// Fangs working on a meal, 0..1.
    var chew: CGFloat = 0
    /// The head tipped up on its neck (+) or down (-), in radians.
    var headTilt: CGFloat = 0
    /// The head cocked over to one side on its neck — the quizzical tilt
    /// of a jumping spider looking at you — in radians as seen on the
    /// screen, + to the left (anticlockwise), whichever way it faces. All
    /// of it shows face on; side on, a roll of the head does not show.
    var headCock: CGFloat = 0
    /// One eye of each pair shut, 0…1: a wink.
    var wink: CGFloat = 0
    /// Its palps — the two little paddles in front of its face — flicked
    /// up (side on) or out (face on), 0…1 each, the near one and the far
    /// one: a jumping spider's tell that it has its eye on something.
    var palpNear: CGFloat = 0
    var palpFar: CGFloat = 0
    /// How much further round than the legs the head and abdomen are
    /// turned, as a yaw: they are drawn at `facing + headTurn`, the legs at
    /// `facing`. Following the pointer, the upper body leads and the legs
    /// come after.
    var headTurn: CGFloat = 0
    /// The abdomen tipped on its waist, tail down (+) or up (-), in
    /// radians: the other end of the body from the head, so looking up it
    /// dips and peering down it rises.
    var abdomenTilt: CGFloat = 0
    /// Windows in front of the surface it is on, in world px: whatever of
    /// the sprite falls inside them is behind them, and is not drawn.
    var hiddenBy: [CGRect] = []
    /// Peek-a-boo, hiding: its two front feet, gripping the edge it is
    /// behind — drawn as little dots, in world px relative to `pos`, even
    /// though the rest of it is cut out by `hiddenBy`.
    var peekGrip: [V2] = []
    /// The weather on it, 0…1 each: soaked (a darker, glossy coat beaded
    /// with water), snow settled on its back, dust in its fur, and chilled
    /// (a bluish tinge).
    var wet: CGFloat = 0
    var snow: CGFloat = 0
    var dust: CGFloat = 0
    var chill: CGFloat = 0
    /// Drips, splashes and puffs round it (see `Speck`).
    var specks: [Speck] = []
}

// MARK: - Legs

private struct Leg {
    var hip: V2
    var rest: V2
    /// Where this leg sits in the gait cycle, 0..1.
    var phase: CGFloat

    /// Foot position in body-local units. During stance it is held still in
    /// world space by cancelling out the body's own motion, which is what makes
    /// the walk read as steps rather than a slide.
    var foot: V2 = .zero
    var footVel: V2 = .zero
    var swinging = false
    var swingFrom: V2 = .zero
    /// Set when the gait clock was already well into this leg's window as
    /// stepping began: it sits this one out rather than start mid-air.
    var skipSwing = false
    /// Where in its window this swing began, so a step that starts a little
    /// late still runs from the ground to the end of the window.
    var swingPh0: CGFloat = 0
    /// A step handed to this leg's mirror twin as the body passed the front
    /// view mid-walk keeps its own timing: how far this slot's gait window
    /// is shifted for it, until it lands. 0 otherwise.
    var swingShift: CGFloat = 0
    /// Which way along the sprite's x the body was going as this step set
    /// off: a foot already in the air lands where it was aimed, even if the
    /// body turns back under it.
    var swingDir: CGFloat = 1
    /// Where a settling step is going: fixed when it begins, so a target
    /// that flickers between two edges near a corner cannot drag the foot.
    var settleTo: V2 = .zero
    var lift: CGFloat = 0
    /// A settling step: standing, a foot left somewhere odd by whatever it
    /// was just doing takes one proper step to its place (0..1 through it,
    /// or -1 for none) instead of sliding there.
    var settle: CGFloat = -1
    /// Where the foot was as the current activity began: a raised pose is
    /// reached from here on an eased path rather than snapped to.
    var poseFrom: V2 = .zero

    /// The refined walk's own steps (see "The refined walk"): how far
    /// through a step in the gait it is, 0…1; where that step is going,
    /// held in place on the ground; how long a step it took out of turn
    /// lasts, in seconds (0 for a settling step something else began);
    /// and when it last came down out of one.
    var swingU: CGFloat = 0
    var swingTo: V2 = .zero
    var stepDur: CGFloat = 0
    var landedAt: CGFloat = -9

    var wobble: Wobble = Wobble()
}

private enum LegMode { case planted, free }

// MARK: - Behaviour

private enum Mode {
    case attached
    case airborne
    case dangling
    case held
    case nesting     // in its silk hammock, building it or asleep in it
    case clinging    // hanging off the pointer, having caught it
}

/// The pointer as prey: the stages of a hunt of the cursor itself.
private enum CursorHunt { case none, stalking, pouncing, clinging }

/// What it is doing on the end of a thread.
private enum WebStyle { case hang, swing }
private enum NestPhase { case building, entering, sleeping, leaving }
private enum HomeGoal { case build, sleep, corner, mend }

/// The silk retreat a jumping spider spins in a sheltered corner: a sling
/// strung across the corner from the wall to the underside of the menu bar,
/// sagging like a hammock, with the corner itself left open behind it.
/// The kinds of retreat it spins. All are a loose, stringy sling between
/// the wall and the ceiling of a top corner; they differ in shape and in
/// how the silk is gathered.
enum HammockStyle: Int, CaseIterable {
    case sling      // a long, shallow band of strands
    case pouch      // a deep bag it can sink right into
    case tangle     // a loose criss-cross of strands with a bed in the middle
    case cradle     // wide and shallow, with loops of silk drooping beneath

    var label: String {
        switch self {
        case .sling: return "sling"
        case .pouch: return "pouch"
        case .tangle: return "tangle"
        case .cradle: return "cradle"
        }
    }
    /// The sag of the middle as a share of the corner's height.
    var sagShare: CGFloat {
        switch self {
        case .sling: return 0.42
        case .pouch: return 0.66
        case .tangle: return 0.5
        case .cradle: return 0.34
        }
    }
    var strands: Int {
        switch self {
        case .sling: return 7
        case .pouch: return 9
        case .tangle: return 6
        case .cradle: return 6
        }
    }
    /// How much further the middle sinks under the spider's weight.
    var give: CGFloat {
        switch self {
        case .sling: return 10
        case .pouch: return 16
        case .tangle: return 8
        case .cradle: return 12
        }
    }
}

struct Hammock: Equatable {
    var left: Bool            // which top corner of the screen
    var rect: CGRect          // world; the sling and its anchors fit inside
    var progress: CGFloat     // 0..1 as it is spun
    var damage: CGFloat       // 0..1 as you wipe it away
    var style: HammockStyle = .sling
    /// The spider's weight in it, 0..1: the middle sinks with it.
    var load: CGFloat = 0
    /// A seed for the strands' wobbles, so every one is a little different.
    var seed: Int = 0
    /// Where along the sling (0..1) its weight sits; nil means the bed.
    /// The silk dips under it there, and the dip goes with it as it walks
    /// the sling.
    var loadU: CGFloat? = nil
    /// How far the middle is swung sideways, px: a breeze, or the spider
    /// shifting about in it.
    var sway: CGFloat = 0
    /// How far each strand has draped, 0..1: a strand just stuck down at
    /// both ends is still the taut line it was walked out as, and sinks to
    /// its sag over a couple of seconds. Missing entries count as settled.
    var drape: [CGFloat] = []

    /// How many longitudinal strands are laid at a given progress — the
    /// first at the first fastening, the rest across the middle of the build.
    static func strandsLaid(progress: CGFloat, of strands: Int) -> Int {
        let laid = progress < 0.30 ? (progress > 0.1 ? 1 : 0)
            : 1 + Int((remap(progress, 0.36, 0.88, 0, CGFloat(strands - 1))).rounded(.down))
        return min(strands, max(0, laid))
    }

    /// Marks any strand newly laid at this progress as taut, to drape from here.
    mutating func startDraping() {
        let n = Hammock.strandsLaid(progress: progress, of: style.strands)
        while drape.count < n { drape.append(0) }
    }

    /// Lets the strands sink; true if anything moved.
    mutating func tickDrape(dt: CGFloat) -> Bool {
        var moved = false
        for i in drape.indices where drape[i] < 1 {
            drape[i] = min(1, drape[i] + dt / 2.4)
            moved = true
        }
        return moved
    }

    /// Out along the ceiling, and down the wall.
    var ceilingAnchor: V2 { V2(left ? rect.maxX - 4 : rect.minX + 4, rect.maxY - 2) }
    var wallAnchor: V2 { V2(left ? rect.minX + 2 : rect.maxX - 2, rect.maxY - rect.height * 0.62) }
    /// How far the middle hangs below the straight line between the anchors.
    var sag: CGFloat { rect.height * style.sagShare }

    /// The area it is drawn in: the corner box, with room below and beside
    /// it for the sag, the loops drooping under it, the extra give under
    /// the spider and the swing. The geometry stays in `rect`.
    var drawFrame: CGRect {
        let below = rect.height * 0.8, side: CGFloat = 30
        return CGRect(x: left ? rect.minX : rect.minX - side, y: rect.minY - below,
                      width: rect.width + side, height: rect.height + below)
    }

    /// The sling's centre line, a quadratic from the wall to the ceiling;
    /// `drop` lowers the control point (torn, or weighed down). On top of
    /// that the silk dips locally under the spider's weight — a hollow
    /// where it lies, deepest on the lowest strands (`strand` 0) so the
    /// sling closes round it — and the whole middle swings with `sway`,
    /// lifting a touch at the ends of a swing as a pendulum does.
    func point(at u: CGFloat, drop: CGFloat = 0, strand: CGFloat = 0) -> V2 {
        let a = wallAnchor, b = ceilingAnchor
        let c = (a + b) * 0.5 + V2(0, -(sag + drop + load * style.give) * 2)
        let v = 1 - u
        var p = a * (v * v) + c * (2 * v * u) + b * (u * u)
        let mid = sin(u * .pi)
        if load > 0.001 {
            let near = 1 - min(abs(u - (loadU ?? bedU)) / 0.32, 1)
            let bell = near * near * (3 - 2 * near)
            p.y -= load * style.give * 1.6 * bell * (1 - 0.4 * strand)
        }
        p += V2(sway, abs(sway) * 0.12) * mid
        return p
    }
    func tangent(at u: CGFloat) -> V2 {
        let a = wallAnchor, b = ceilingAnchor
        let c = (a + b) * 0.5 + V2(0, -(sag + load * style.give) * 2)
        return ((c - a) * (1 - u) + (b - c) * u).normalized
    }
    /// Where along the sling the lowest point is (the wall end is lower
    /// than the ceiling end, so it is not the middle).
    var bedU: CGFloat {
        let a = wallAnchor.y, b = ceilingAnchor.y
        let c = (a + b) * 0.5 - (sag + load * style.give) * 2
        let denom = a - 2 * c + b
        guard abs(denom) > 0.001 else { return 0.5 }
        return clamp((a - c) / denom, 0.15, 0.85)
    }
    /// The bottom of the sag, where it lies.
    var bed: V2 { point(at: bedU) }

    /// Where along the sling (0..1) is nearest `p`.
    func nearestU(to p: V2) -> CGFloat {
        var best: (u: CGFloat, d: CGFloat) = (0, .greatestFiniteMagnitude)
        for k in 0...40 {
            let u = CGFloat(k) / 40
            let d = point(at: u).distance(to: p)
            if d < best.d { best = (u, d) }
        }
        // Refine between the neighbours.
        for k in 1...8 {
            let step = 0.025 / CGFloat(k)
            for u in [best.u - step, best.u + step] where u >= 0 && u <= 1 {
                let d = point(at: u).distance(to: p)
                if d < best.d { best = (u, d) }
            }
        }
        return best.u
    }
    /// The nearest point on the sling's centre line to `p`.
    func nearest(to p: V2) -> V2 { point(at: nearestU(to: p)) }
}

/// Everything it can be doing while standing on something.
private enum Activity {
    case idle
    case walk       // ordinary crawl, with a speed picked per bout
    case sneak      // low, slow, stalking
    case scurry     // a burst of speed
    case look       // stops and glances about
    case rest       // settles low, breathing slowly
    case groom      // wipes its face with a front leg
    case sleep
    case wave
    case startle
    case crouch     // gathering itself before a leap, with the pounce wiggle
    case turn       // turning round, with a hop or a shuffle
    case peek       // leaning out over the end of a ledge
    case stretch    // a big stretch on waking
    case shake      // shaking itself off
    case wiggle     // happy abdomen wiggle
    case bounce     // little excited hops
    case curious    // leaning toward the pointer, front legs up
    case fidget     // tapping a front foot
    case scratch    // a back leg scratching the abdomen
    case armsUp     // both front legs thrown up: a greeting, or a threat display
    case roll       // tucks up into a ball and rolls along the ledge
    case dance      // a little side-to-side dance with the abdomen going
    case glance     // turns three-quarters toward you for a look
    case peer       // nose down to the ledge, examining something
    case pushup     // dips and rises on its legs
    case legStretch // one back leg out behind it, then the other
    case spin       // a quick full spin — two turns back to back
    case shoot      // firing a line at something above, before a swing
    case eat        // a meal: the catch held to the mouth, fangs working
    case watch      // settled down, eyes on the screen: a full-screen video is on
    case fasten     // spinning: abdomen pressed to the surface, sticking silk down
    case peekaboo   // hiding behind a window's edge and popping out at you
    case greet      // turns to face you square on and raises both front legs
    case drum       // drums on the surface with both front legs
    case stare      // sits still, turned to face you, watching
    case hop        // a small nervous hop on the spot
    case groove     // dancing to music playing on the Mac, on its beat
    case brace      // hunkered down low, legs spread, against a gust or a downpour
    case bask       // stretched out low in the sun, eyes half shut
    case feel       // front legs out to something in front of it, feeling it (see `feelAt`)
    case drink      // head down to water, front legs at its edge, sipping (see `sipAt`)
    case doubleTake // a look at you, away again — and a snap back round to stare (see "Body language")
    case sigh       // a big breath in, and out: a slump on its legs
}

/// How it carries itself on a given walk.
private enum GaitStyle { case normal, bouncy, tiptoe, lumber }

private enum AirKind { case jump, fall, thrown }
private enum TurnStyle { case hop, shuffle }

// MARK: - Spider

final class Spider {
    var config = SpiderConfig()
    private(set) var map: SurfaceMap
    /// Living in the habitat window rather than on the desktop. Desktop
    /// things — the hammock, the box, full-screen manners, the laser — do
    /// not apply in there.
    private(set) var inHabitat = false
    /// What it is standing on — the loop, the segment, how far along, and
    /// which way it is walking — while it stands on something; nil in the
    /// air, on a line, or in your hand.
    var standingOn: Anchor? {
        guard mode == .attached, !isHeld else { return nil }
        var a = anchor
        a.dir = walkDir
        return a
    }
    /// The studio's design: how it looks, who it is, how it walks.
    var look = SpiderLook()
    /// What is behind it right now, as told by whoever can see the screen;
    /// a camouflaged coat drifts toward it rather than snapping.
    var surroundings = SpiderPose.defaultSurroundings
    private var shownSurroundings = SpiderPose.defaultSurroundings
    /// Whether it is standing on a window, as opposed to the screen edge,
    /// the Dock or the menu bar.
    var standingOnWindow: Bool {
        guard mode == .attached, let loop = map.loop(anchor.loopID) else { return false }
        return loop.kind.onWindow
    }
    /// Who it is: the Studio's personality, shifted a little by what it has
    /// been through (see Memory.swift). Everything it decides reads this.
    private(set) var personality = Personality() {
        didSet { config.liveliness = personality.liveliness }
    }
    /// The Studio's personality, which nothing it learns ever changes.
    private(set) var basePersonality = Personality()
    /// What it has been through. Nil — a visitor, the Studio's preview, the
    /// tools, or with learning turned off — and it is just as the Studio
    /// made it.
    var memory: SpiderMemory? {
        didSet {
            memory?.settle(base: basePersonality)
            refreshTemperament()
        }
    }
    /// The shift its memories make right now: zero without any.
    private(set) var learned = TraitShift.zero
    private var memoryDue: CGFloat = 0
    var gait = Gait()
    var habits = Habits()
    /// 0…1: how run down it feels, up while the Mac is in Low Power Mode. It
    /// makes up its mind less often, rests and naps more and dashes about
    /// less — which is fewer frames to draw, too.
    var drowsy: CGFloat = 0
    /// It is raining outside: rain is on its mind.
    var raining = false {
        didSet {
            if raining, !oldValue, mode == .attached, activity != .sleep, emote == .none {
                think(.rain, for: 3.5)
            }
        }
    }
    /// The weather it is out in: the habitat's, while it is in there; calm
    /// anywhere else. It takes notice as things arrive (see "Weather").
    var weather = WeatherFeel.calm {
        didSet { if weather != oldValue { weatherArrived(oldValue) } }
    }
    /// How wet it is, how much snow has settled on it and how dusty it is,
    /// 0…1 each — all of which it shakes off — and how chilled.
    private(set) var wet: CGFloat = 0
    private(set) var snowOn: CGFloat = 0
    private(set) var dust: CGFloat = 0
    private(set) var chill: CGFloat = 0
    /// Under something that keeps the weather off (see `isSheltered`),
    /// looked at now and then.
    private(set) var sheltered = false
    private var shelterCheckIn: CGFloat = 0
    /// What is dripping and splashing off it, in the world.
    private struct Drop {
        var p: V2
        var v: V2
        var r: CGFloat
        var kind: Speck.Kind
        var life: CGFloat
        var age: CGFloat = 0
        /// The height it splashes at, falling (nil: it only fades).
        var floor: CGFloat?
        /// Still gathering on it: this long to go, and where on the body,
        /// in sprite units.
        var hold: CGFloat = 0
        var at: V2 = .zero
        var gravity: CGFloat = 900
        /// A ring: how far it spreads (its radius grows to 1 + this times).
        var spread: CGFloat = 1.2
        /// A drop it is drinking (on a leaf): it sits where it is, and
        /// shrinks as it drinks.
        var sip = false
    }
    private var drops: [Drop] = []
    private var dripIn: CGFloat = 0
    private var splashIn: CGFloat = 0
    private var hailIn: CGFloat = 1
    private var lastShakeOff: CGFloat = -99
    private var shookAt: CGFloat = -99
    /// Heading for cover from the weather, and where.
    private var coverGoal: (anchor: Anchor, point: V2)?
    private var coverSince: CGFloat = 0
    /// Its eyes up at the sky, until then: a rainbow, a flash, the flakes.
    private var skyLookUntil: CGFloat = -1
    private var lastSkyLook: CGFloat = -99
    /// The wind on it, eased: what it leans into.
    private var windOn = Spring(0, stiffness: 40, damping: 9)
    private var braceAfter: CGFloat = 0

    var name = "Spider"
    private var nameTag = Spring(0, stiffness: 60, damping: 12)
    private var hoverFor: CGFloat = 0
    private var odometer: CGFloat = 0

    // Kinematics
    private var pos = V2(400, 400)
    private var vel = V2.zero
    private var heading: CGFloat = 0
    private var headingVel: CGFloat = 0
    private var headingTarget: CGFloat = 0
    /// Which way it is facing along the surface, +1 or -1.
    private var facing: CGFloat = 1
    /// How far round it has turned, animated: +1 and -1 are the two profiles,
    /// 0 is facing the viewer. A turn sweeps this through zero; `facing` flips
    /// as it crosses.
    private var yaw: CGFloat = 1
    private var turnFromYaw: CGFloat = 1
    /// A gait clock that runs only during a turn, so the feet step round.
    private var turnGait: CGFloat = 0
    private var grounded = Spring(0, stiffness: 120, damping: 18)

    // Posture. Every activity sets targets for these and springs carry the
    // body between them, so nothing ever snaps from one stance to another.
    private var lift = Spring(0, stiffness: 140, damping: 21)      // height off the ledge
    private var pitch = Spring(0, stiffness: 120, damping: 20)     // nose up (+) / down (-)
    /// A touch of nose-down when running, folded into the body lean.
    private var runNose: CGFloat = 0
    /// Lean from getting going and pulling up (+ = rocking back).
    private var inertia: CGFloat = 0
    private var walkPauseAt: CGFloat = 99
    /// What the walk was for: done once it gets there.
    private var walkThen: (Activity, CGFloat)?
    private var walkPauseFor: CGFloat = 0
    /// Where a leap is going to land, if it knows: it turns and reaches for
    /// the surface over the last stretch of flight instead of snapping on.
    private var landing: (point: V2, angle: CGFloat, dir: V2)?
    private var landingReach: CGFloat = 0
    /// The roll: distance travelled while balled up, which is what turns it.
    private var rollTravel: CGFloat = 0
    private var rollSpinEnd: CGFloat = 0
    private var rollLanded = false
    private var rollTouched = false
    /// How far it is balled up, 0..1.
    private var ball: CGFloat = 0
    private var crouch = Spring(0, stiffness: 200, damping: 25)
    private var wag = Spring(0, stiffness: 90, damping: 12)        // abdomen wiggle amplitude
    private var wagPhase: CGFloat = 0
    private var stretch = Spring(1, stiffness: 320, damping: 20)
    private var fatten = Spring(1, stiffness: 320, damping: 20)
    private var lookSpring = Spring2(.zero, stiffness: 150, damping: 16)
    private var happy = Spring(0, stiffness: 120, damping: 14)
    private var startled = Spring(0, stiffness: 190, damping: 17)
    private var sleepiness = Spring(0, stiffness: 40, damping: 12)
    private var lid = Spring(0, stiffness: 60, damping: 13)        // heavy eyelids
    private var grabbed = Spring(0, stiffness: 200, damping: 18)

    // State
    private var mode: Mode = .airborne
    private var air: AirKind = .fall
    /// Tools only: no bouncing at all, to compare with how it was.
    static var debugNoBounce = ProcessInfo.processInfo.environment["SPIDER_NO_BOUNCE"] != nil
    /// Tools only: bounces so far, and how fast it is tumbling.
    private(set) var debugBounces = 0
    var debugTumble: CGFloat { tumbleVel }
    /// End over end after a hard bounce, in radians a second; dies away,
    /// and gives way to turning feet first once a landing is near.
    private var tumbleVel: CGFloat = 0
    private var activity: Activity = .idle
    private var queued: (Activity, CGFloat)?
    private var anchor = Anchor(loopID: "", segIdx: 0, t: 0)
    private var walkDir: CGFloat = 1
    private var pendingDir: CGFloat = 1
    private var turnStyle: TurnStyle = .hop
    private var turned = false
    private var speed: CGFloat = 0
    private var targetSpeed: CGFloat = 0
    private var bout: CGFloat = 1                 // per-walk speed multiplier
    private var boutBob: CGFloat = 1
    private var boutStride: CGFloat = 28
    /// The stride actually being taken: the bout's own, lengthened once the
    /// pace would have the legs cycling faster than `maxCadence` — a
    /// hurrying spider reaches further, it does not only step quicker, and
    /// a foot that is in the air for two frames reads as a flicker.
    private var strideNow: CGFloat {
        let stride = max(boutStride, speed / max(config.scale, 0.05) / Spider.maxCadence)
        // Walking the refined way, no stance is longer than all eight legs
        // can take at their own lengths: past that it steps quicker.
        if refinedWalk { return min(stride, refSweep / (1 - refSwing)) }
        // Walking the natural way, no foot is ever carried further than its
        // leg can reach: past that it steps quicker instead.
        guard naturalWalk else { return stride }
        return min(stride, natSweep / (1 - natDuty))
    }
    private static let maxCadence: CGFloat = 3.6
    private var gaitStyle: GaitStyle = .normal
    private var speedWobble = Wobble(seed: 17, freq: 0.9)
    private var liftWobble = Wobble(seed: 23, freq: 0.35)
    /// 0 = full profile, up to ~0.7 = turned three-quarters toward the viewer.
    private var glance: CGFloat = 0
    private var glanceIn: CGFloat = 4
    private var glanceUntil: CGFloat = 0
    /// How far round a glance (the activity) turns it this time: never
    /// quite the same twice.
    private var glanceDepth: CGFloat = 0.62
    private var rollSpin: CGFloat = 0


    // Timers
    private var t: CGFloat = 0
    private var activityTime: CGFloat = 0
    private var activityDur: CGFloat = 1
    private var activityStarted: CGFloat = -9
    /// Gestures whose legs come up off the ledge: they rise into the pose
    /// over this long, and settle back to standing over the last stretch,
    /// so a wave or a tap begins and ends as a movement rather than a cut.
    private static let poseEaseIn: CGFloat = 0.42
    private static let poseEaseOut: CGFloat = 0.32
    private static let easedPoses: Set<Activity> = [.wave, .curious, .armsUp, .dance, .drum, .fidget, .scratch,
                                                    .groom, .legStretch, .greet, .eat, .sleep, .stretch, .feel, .drink]
    private var decisionIn: CGFloat = 1.2
    private var airTime: CGFloat = 0
    private var noAttachFor: CGFloat = 0
    private var launchLoop: String = ""
    private var blinkIn: CGFloat = 2
    private var blinkT: CGFloat = -1
    private var blinkTwice = false
    private var occludedFor: CGFloat = 0
    private var offScreenFor: CGFloat = 0
    /// An escape from under a window is under way until then: the covered
    /// check must not keep restarting it, which is what used to freeze it
    /// mid-crouch.
    private var escapeUntil: CGFloat = 0
    /// What a fired line is for: a swing, or a straight climb out of the way.
    private enum ShotPurpose { case swing, climb }
    private var shotPurpose: ShotPurpose = .swing
    /// Climbing out from under a window: hauls at double pace.
    private var hurrying = false
    /// A fall it means to catch: the dragline fastened where it let go
    /// pays out as it drops, and it takes hold at this height — decided
    /// before it dropped, and well clear of whatever is below.
    private var draglineCatchY: CGFloat?
    /// A line shot up in mid-air: let go of with nothing fastened to it,
    /// it twists to bring its spinnerets round to a mark on the ceiling,
    /// the line races out to it, and once it has caught it takes hold at
    /// `catchY` — at an angle, so it swings.
    private struct AirShot {
        var target: V2
        var depth: Int
        var catchY: CGFloat
        var began: CGFloat
        var progress: CGFloat = 0
    }
    private var airShot: AirShot?
    /// The twist before the shot, and the line's flight, in seconds.
    static let airShotAim: CGFloat = 0.14
    static let airShotFlight: CGFloat = 0.2
    /// A throw this fast (px/s) is a proper fling: it rides it out rather
    /// than shooting a line. A hand moving the pointer at all quickly is
    /// already well over a thousand, so only a real flick counts.
    static let hardThrow: CGFloat = 1800

    // Food
    /// Everything loose on the desktop to hunt, plus whatever it is eating.
    private(set) var prey: [Prey] = []
    private var nextPreyID = 1
    private var huntTarget: Int?
    private var huntSince: CGFloat = 0
    private var huntPauseUntil: CGFloat = 0
    /// The current leap is a pounce at the prey, and where it was aimed.
    private var huntPounce = false
    private var pounceMark: V2?
    private var lastPounceAt: CGFloat = -10
    /// Hunting decisions that got it nowhere in a row: time to try another way.
    private var huntStalls = 0
    private var huntLastPos = V2.zero
    private var caught: Prey?
    /// How well fed it is, 0..1: a good meal keeps it cheerful for a while.
    private(set) var fed: CGFloat = 0
    private var lastUserActivity: CGFloat = 0
    private var lastCurious: CGFloat = -10
    /// The big gestures — a greeting, arms up, a wave, feeling the air, a
    /// happy wiggle or dance — mean something because they are rare: one,
    /// then a good while before the next of its own accord, and seldom the
    /// same one twice running. (A click still gets an answer at once.)
    private static let gestures: Set<Activity> = [.greet, .armsUp, .wave, .curious, .wiggle, .dance, .bounce]
    private var lastGestureAt: CGFloat = -99
    /// Which pair of legs a raised-legs gesture lifts, picked as it begins:
    /// seen side on, its two front legs; turned toward you, the outermost
    /// pair, one either side of its face. (Raised by the side-on choice when
    /// it is face on, both would be on the same side of it, and it would be
    /// standing on one side's legs alone.)
    private var liftsOuterPair = false

    /// Where a leg that stays down stands for however the body is turned —
    /// braced a little wider when it is taking the weight of a raised leg.
    private func standingFoot(_ i: Int, braced: Bool) -> V2 {
        let f = SpiderRenderer.rig(i, profile: SpiderRenderer.profileAmount(yaw: yaw), look: look).foot
        guard braced else { return f }
        return V2(f.x + (f.x >= legs[i].hip.x ? 3 : -3), f.y)
    }

    /// Face on, the other two near-side legs (0 and 3) start under the face
    /// too: left on the ledge they would cross in front of it on the way
    /// down and look like a front leg still standing. With the front legs
    /// up they come up and out to the sides as well — it stands on its
    /// four far legs, behind it on both sides. Nil for any other leg.
    private func faceOnOuter(_ i: Int) -> V2? {
        guard i == 0 || i == 3 else { return nil }
        let side: CGFloat = i == 0 ? 1 : -1
        let a = t * 3 + (side > 0 ? 0.4 : 1.1)
        legBend[i] = V2(side, 0.7)
        legBones[i] = 0
        return legs[i].hip + V2(side * (31 + sin(a) * 1.2), 10 + cos(a) * 1.5)
    }

    /// `t` of the way from `a` to `b`, swung round `h` (angle and reach
    /// blended) rather than along the straight line between them.
    static func swing(_ a: V2, _ b: V2, about h: V2, _ t: CGFloat) -> V2 {
        let va = a - h, vb = b - h
        guard va.length > 1, vb.length > 1 else { return V2.lerp(a, b, t) }
        let ang = va.angle + angleDelta(va.angle, vb.angle) * t
        return h + V2.angle(ang) * lerp(va.length, vb.length, t)
    }

    /// A front leg raised face on: the foot `out` to its side of the face
    /// and `up`, from its own hip, knee bent outward — and drawn with the
    /// same proportions on both sides (leg 0's), since the face-on layout
    /// gives the two front legs different lengths, and a raised pair should
    /// match.
    private func faceOnRaise(_ i: Int, side: CGFloat, out: CGFloat, up: CGFloat) -> V2 {
        legBend[i] = V2(side, 0.2)
        legBones[i] = 0
        return legs[i].hip + V2(side * out, up)
    }

    /// For a gesture that raises two legs: nil for a leg that stays down,
    /// else which way that leg's foot goes — +1 out ahead (side on), or
    /// the side of the face it is on (face on).
    private func raisedSide(_ i: Int) -> CGFloat? {
        if liftsOuterPair {
            // Face on, its front legs are the inner near pair, 1 and 2 — the
            // ones whose knees come forward in front of the face, one either
            // side of it. (The outer feet, 0 and 3, read as side legs; 4–7
            // are the far side, behind the body.)
            guard i == 1 || i == 2 else { return nil }
            return SpiderRenderer.frontLegs[i].foot.x >= 0 ? 1 : -1
        }
        return i % 4 == 0 ? 1 : nil
    }
    private var lastGesture: Activity = .idle
    private var gestureGap: CGFloat = 0
    private var gestureReady: Bool { t - lastGestureAt > gestureGap }
    /// The weight multiplier for starting gesture `a` on its own.
    private func gestureWeight(_ a: Activity) -> CGFloat {
        guard gestureReady else { return 0 }
        return a == lastGesture ? 0.25 : 1
    }
    private var restedFor: CGFloat = 0
    private var wokeUp = false
    private var idleLook = V2.zero
    private var idleLookIn: CGFloat = 0
    /// Position in the gait cycle, in whole cycles.
    private var gaitPhase: CGFloat = 0
    /// Direction of travel in body-local units. Forward is always +x; turning
    /// round is a mirror, not a rotation.
    private var travelLocal = V2(1, 0)
    /// Smoothed attachment point, before the walking bob is added.
    private var anchorPos = V2.zero
    /// How hard the body is pulled onto the ledge: tight when walking, so
    /// a dragged window carries it, loose just after a landing so it
    /// gathers itself onto the edge instead of snapping there.
    private var anchorGlide: CGFloat = 45
    private var landedAt: CGFloat = -9
    /// Just landed and still coming down onto the ledge: the body keeps
    /// falling until the legs take its weight.
    private var landDrop = false
    /// How long the feet take to reach the ledge after a landing: they get
    /// there just as the body does.
    private var landStep: CGFloat = 0.1
    /// The lurch along the ledge as a landing is absorbed: the body carries
    /// on the way it was going over its planted feet, then comes back.
    private var skid = Spring(0, stiffness: 140, damping: 21)
    /// How long after a landing the planted feet hold their place in the
    /// world while the body moves over them.
    private static let landHold: CGFloat = 0.5
    /// Still taking a landing: the one time every foot goes for the ledge
    /// at once, and fast — however it came in, it has all eight down by the
    /// time the body has stopped.
    private var absorbingLanding: Bool { mode == .attached && t - landedAt < Spider.landHold }
    /// The last landing was the top of a climb: it stepped up onto the
    /// ledge off its line rather than coming down on it.
    private var climbedOnto = false
    /// How much faster than a step a foot or knee may pick up speed taking
    /// a landing: a fall is taken all at once; a climber steps up.
    private var landingJolt: CGFloat { absorbingLanding && !climbedOnto ? 3 : 1 }
    /// How much of the impact speed the body keeps once the legs have it.
    private static let landAbsorb: CGFloat = 0.35
    /// The lowest the body can sink toward the ledge, in points: its
    /// belly and chin stay clear of the surface, whatever shape it is —
    /// and however it is tilted, still swinging square to the ledge out
    /// of a landing, when the nose or the tail hangs lower.
    private func maxSink(tilt: CGFloat) -> CGFloat {
        let m = look.bodyMetrics
        let a = SpiderRenderer.abdomen, h = SpiderRenderer.head
        let points = [V2(a.c.x, a.c.y - a.ry * m.ary), V2(a.c.x - a.rx * m.arx, a.c.y),
                      V2(h.c.x, h.c.y - h.r * m.head), V2(h.c.x + h.r * m.head, h.c.y)]
        // The lowest point in the ledge's frame: the sprite is squashed
        // about its ground line and mirrored, as drawn, then turned by
        // however far off the ledge's line the body is.
        let (sx, sy) = bodySquash()
        let g = SpiderRenderer.ground
        let low = points.map { ($0.x * sx * mirrorSign) * sin(tilt) + (g + ($0.y - g) * sy) * cos(tilt) }.min()!
        return clamp(low - g - 2, 0, 7) * config.scale
    }
    private var anchorValid = false
    private var surfaceNormal = V2(0, 1)
    private var legFramePos = V2.zero
    private var legFrameHeading: CGFloat = 0
    /// The body's motion this frame over its planted feet, in sprite
    /// space — everything but the surface itself moving (a window being
    /// dragged carries the feet with it) — and its turn, for feet holding
    /// their place in the world to cancel out.
    private var legOverFeet = V2.zero
    private var legDTheta: CGFloat = 0
    /// How fast the body is turning in the world, radians a second.
    private var bodySpin: CGFloat = 0
    /// How far the surface under it moved this frame, in world points.
    private var legSurfaceWorld = V2.zero
    /// Where the anchor point on the surface was last frame, to tell the
    /// surface moving from the body moving.
    private var surfacePrev: V2?
    private var surfaceMotion = V2.zero
    private var emote: Emote = .none
    private var thought: Thought = .heart
    private var lastThought: CGFloat = -30
    /// Heading for a window top to sleep on: sleep soon after landing.
    private var bedBoundUntil: CGFloat = -1
    /// The thoughts it may have in words (from the design).
    var packs: [ThoughtPack] = [.chitchat]
    var customPhrases: [String] = []
    private var emoteTime: CGFloat = 0
    private var emoteClock: CGFloat = 0
    private var emoteDur: CGFloat = 0
    /// Set when a walk runs out of ledge, so the spider can react to it.
    private var reachedEnd = false
    private var lastLoopRect: CGRect?
    private var stuckPos = V2.zero
    private var stuckFor: CGFloat = 0

    // Web
    private var webStyle: WebStyle = .hang
    private var swingHalfSwings = 0
    private var swingReleaseAt: CGFloat = 0.5
    /// What it means to do on a line: a short list of intentions it works
    /// through in order, so time on a thread reads as one idea — down for a
    /// look, a while hanging there, then home — rather than a fresh whim
    /// every few seconds.
    private enum WebPlan {
        case descend(CGFloat)   // pay out to this length
        case linger(CGFloat)    // hang about for this long
        case climbHome          // haul back up to whatever it hung from
        case toFloor            // all the way down and step off
        case swing              // work up a swing and let go
        case jumpOff            // spring off the line to somewhere near
        case swingOff(CGFloat)  // the top is gone: pay out to this length, swing up and let go
    }
    private var webPlan: [WebPlan] = []
    private var lingerUntil: CGFloat = -1
    private var lingerNext: CGFloat = 0
    private var floorWait: CGFloat = -1
    /// Body centre relative to the point on the line the spinnerets hold.
    private var hangOff: V2 = .zero
    private var hangOffFresh = true
    /// Just taken to a line fastened beside or below it, and still falling
    /// round under it.
    private var fallingRound = false
    /// Stepped off the top of something on its dragline to go down it: when
    /// the line takes its weight, it carries on down.
    private var rappelAfterCatch = false
    /// ...and it stepped off to go down and see the pointer below it.
    private var pointerDrop = false
    /// Told which way to go by the scroll wheel (see `scroll`). Told to go
    /// up, it goes all the way up and off the top; told to go down its
    /// line, all the way down to the next thing below it can stand on; told
    /// to go down off a ledge (`drop`), half way down to whatever is below,
    /// and it hangs there. None of it does it change its mind about part
    /// way; the drop, once it is hanging there, is done with.
    private enum LineOrder { case up, down, drop }
    private var lineOrder: LineOrder?
    private var orderedAt: CGFloat = -99
    /// The scroll gesture under way: how far it has gone, when the last of
    /// it came, and the way it has already sent it (±1, 0 none yet). One
    /// swipe — however long it runs on for — is one order.
    private var scrollSum: CGFloat = 0
    private var scrollLast: CGFloat = -99
    private var scrollGave: CGFloat = 0
    private var swingReleaseAfter = 1
    private var lastSwingVelSign: CGFloat = 0
    private var swingFromLoop = ""
    /// Depth of whatever it hung its line from: windows in front of that
    /// cover it, the rest are behind the line.
    private var webFromDepth = Int.max
    /// Amplitude of the last half-swing, so the release point scales with it.
    private var swingPeak: CGFloat = 0.5
    /// Working a swing up: it pumps in time with the motion until the arc
    /// reaches the amplitude it wants, then rides it and lets go.
    private var swingPumping = false
    private var swingTargetPeak: CGFloat = 1.0
    private var swingPumpUntil: CGFloat = 0
    /// Elastic give in the line: a bounce on the end of it.
    private var bungee = Spring(0, stiffness: 34, damping: 2.6)
    /// Pleased on a line: a bounce on the end of it and a happy kick of the
    /// legs hanging free, until then.
    private var lineJoyUntil: CGFloat = 0
    private var prevHangLen: CGFloat = 0
    /// How far it moved along the line this frame by paying silk out or
    /// hauling it in, px, + = away from the anchor (descending). A bounce
    /// on the end of the line does not count: that stretch is the silk's,
    /// and whatever the legs hold of it goes with the body.
    private var hangDelta: CGFloat = 0
    /// The climbing gait's phase, in strides, run on distance hauled in;
    /// and the hind legs' stroke feeding silk out, run on time.
    private var climbPhase: CGFloat = 0
    private var feedPhase: CGFloat = 0
    /// Head up the line only while it is hauling itself up; otherwise it
    /// hangs head down, the way a spider on a dragline does.
    private var hangHeadUp = false
    /// How far round it has come to face up the line: 0 hanging head down,
    /// 1 head up, and in between while it turns end for end.
    private var upness: CGFloat = 0
    /// Which way it is turning end for end on the line, ±1, while it does.
    private var flipSign: CGFloat = 0
    /// Turning end for end, it first takes the line in to its middle — the
    /// hind legs draw it in against the belly — and turns about that, its
    /// weight under its own grip, rather than swinging its body round the
    /// tip of its abdomen: 0 held where it hangs (or climbs) from, 1 drawn
    /// in to its middle (see `turnPivot`).
    private var lineGrip: CGFloat = 0
    /// Where the line was fastened to the body last frame, in sprite units.
    /// When that moves — drawn in to turn, let back out after — the line is
    /// measured again from there, so the body stays where it is.
    private var attachWas: V2?
    /// How much longer the line reads, measured to where it is fastened to
    /// the body now, than it did hanging from the spinnerets: lengths it
    /// means to go to are in those terms (see `reattach`).
    private var lineRef: CGFloat = 0
    /// Taking hold of the line or letting go of it to turn, the way each
    /// foot is going round its hip (see `roundHip`).
    private var gripTurn: [CGFloat?] = []
    /// Where each foot holding the line has hold of it: sprite units along
    /// it from the spinnerets toward the anchor. A foot keeps its place on
    /// the silk while the body goes past it, so this changes only with how
    /// far the body has moved along the line.
    private var lineS: [CGFloat] = Array(repeating: 0, count: SpiderRenderer.legCount)
    private var lineSwingFrom: [CGFloat] = Array(repeating: 0, count: SpiderRenderer.legCount)
    /// A leg hanging free on the line is a weight on the end of a limb:
    /// where its foot is in the world, and how fast it is going, so it
    /// swings with the body rather than being carried rigidly with it.
    private var freeFoot: [V2] = []
    private var freeFootVel: [V2] = []
    /// Hanging still, a hind foot shifts its hold now and then.
    private var regripIn: CGFloat = 2
    private var regripLeg = -1
    private var regripT: CGFloat = 0
    /// The line where it meets the body, in sprite space, pointing toward
    /// the anchor: what the feet hold, and what the held stretch is drawn
    /// along.
    private var lineDirLocal = V2(-1, 0)
    private var stillFor: CGFloat = 0
    private var shotTarget: V2 = .zero
    private var shotProgress: CGFloat = 0
    private var webAnchor: V2 = .zero
    private var webActive = false
    private var webLen: CGFloat = 60
    private var webLenTarget: CGFloat = 60
    private var webAngle: CGFloat = 0
    private var webAngleVel: CGFloat = 0
    private var webAlpha = Spring(0, stiffness: 120, damping: 16)
    private var webGrace: CGFloat = 0
    /// The line itself, as a soft chain of points.
    private var rope = SilkRope()
    /// Which way each leg's knee should bend when it is holding the line,
    /// in sprite units; nil means the ordinary walking knee.
    private var legBend: [V2?] = Array(repeating: nil, count: SpiderRenderer.legCount)
    /// Whose proportions a leg is drawn with this frame, if not its own
    /// (see `faceOnRaise`).
    private var legBones: [Int?] = Array(repeating: nil, count: SpiderRenderer.legCount)
    /// Each knee's shape, eased (see `updateKnees`), and where that puts
    /// the knee, as drawn.
    private var kneeShape: [V2] = []
    private var kneeLocal: [V2] = []
    private var kneeWorld: [V2] = []
    private var kneeWorldVel: [V2] = []

    // Jump bookkeeping
    private var pendingJump: V2?

    /// Some app has the whole display — a video, most likely. Cinema
    /// manners: it settles on the floor (or the ceiling) of the screen and
    /// watches with you, wandering a little now and then; no leaping,
    /// swinging, silk or hunting until the show is over.
    var fullScreenApp = false {
        didSet {
            guard fullScreenApp != oldValue else { return }
            cinemaSince = t
            cinemaSeat = nil
            if fullScreenApp {
                homing = nil
                huntTarget = nil
                pendingJump = nil
                // Whatever it was thinking can wait until after the show.
                if emote == .thought { emote = .none }
                if mode == .attached {
                    queued = nil
                    if activity != .eat { activity = .idle; activityTime = 0 }
                    decisionIn = min(decisionIn, 0.5)
                }
                if mode == .dangling {
                    // Off the line: down to the floor.
                    detachWeb(fade: true)
                    mode = .airborne
                    air = .fall
                    airTime = 0
                    noAttachFor = 0.05
                    legMode = .free
                }
            } else {
                if homing == .corner { homing = nil }
                if activity == .sleep && mode == .attached { wake() }
                if activity == .watch && mode == .attached { activity = .idle; activityTime = 0 }
                decisionIn = min(decisionIn, 1.0)
            }
        }
    }
    private var cinemaSince: CGFloat = 0

    /// Peek-a-boo: the edge it hides behind (t along its segment), which way
    /// along the segment is "behind", the stage of the game and how many
    /// pops it has done.
    private struct Peek {
        var edgeT: CGFloat
        var into: CGFloat
        var stage = 0           // 0 up to the edge, 1 hide, 2 wait, 3 pop out, 4 wait
        var stageTime: CGFloat = 0
        var pops = 0
        var wanted = 3
        var target: CGFloat = 0
    }
    private var peek: Peek?
    /// How fast it is moving itself along the edge during the game, px/s.
    private var peekPace: CGFloat = 0
    /// A peek-a-boo was asked for (the menu) but there was no edge here:
    /// keep trying for a while after it moves.
    private var wantsPeekabooUntil: CGFloat = -1

    /// Its patch: a box it always comes back to. It is not a cage — a
    /// throw or a fall can take it outside — but whenever it finds itself
    /// out, getting back in is the first thing on its mind, and inside it
    /// takes things easy: fewer, gentler decisions, no swinging about, no
    /// hammock trips, and leaps only to spots inside. A box with nothing in
    /// it to stand on, it hangs in from the top of, swaying a little.
    var confine: CGRect? {
        didSet {
            guard confine != oldValue else { return }
            homing = nil
            huntTarget = nil
            boxSurfacesChecked = -99
            if mode == .attached { decisionIn = min(decisionIn, 0.5) }
        }
    }
    private var confined: Bool { confine != nil && !inHabitat }
    private var inBox: Bool { inHabitat || (confine.map { $0.contains(pos.point) } ?? true) }
    /// Whether there is anything to stand on inside the box (checked now
    /// and then; the desktop changes).
    private var boxHasSurfaces = true
    private var boxSurfacesChecked: CGFloat = -99
    /// Confined with nothing to stand on: it lives on a line from the top.
    private var hangOnly: Bool {
        guard let box = confine, !inHabitat else { return false }
        if t - boxSurfacesChecked > 2 {
            boxSurfacesChecked = t
            boxHasSurfaces = map.sampleSpots(spacing: 30).contains { box.contains($0.point.point) }
        }
        return !boxHasSurfaces
    }
    private var swayPhase: CGFloat = 0
    /// The body's velocity on the line, smoothed.
    private var swingVel = V2.zero
    private var hungSince: CGFloat = -99
    private var outOfBoxSince: CGFloat = -1
    /// The short way round its edge back to the box was blocked: go the long way.
    private var returnTheLongWay = false
    private var headTilt = Spring(0, stiffness: 180, damping: 20)
    /// Where it sits to watch a film: the nearest of the four corners of
    /// the screen, or the door of its hammock. Nil until it has picked one.
    private var cinemaSeat: V2?
    private var cinemaSeatIsNest = false
    private var hammockSwayVel: CGFloat = 0
    private var breezeIn: CGFloat = 8
    private var shiftIn: CGFloat = 10
    /// How fast it crawls to its seat, as a fraction of its walk: no hurry.
    static let cinemaPace: CGFloat = 0.6
    /// Cinema manners apply on a screen some app has taken whole.
    private var inCinema: Bool { !inHabitat && (fullScreenApp || map.isCinema(pos)) }

    // Hammock
    private(set) var hammock: Hammock?
    private var homing: HomeGoal?
    /// Spinning the hammock, on the real walls: which leg of the job it is
    /// on. It walks the corner between the wall anchor and the ceiling
    /// anchor, sticking the silk down at each end, one strand per crossing.
    private enum BuildStep { case fastenWall, toCeiling, fastenCeiling, toWall }
    private var build: BuildStep?
    private var buildStrand = 0
    /// The live thread being laid: silk runs from here to the spinnerets.
    private var buildThreadFrom: V2?
    private var homingSince: CGFloat = 0
    private var nestPhase: NestPhase = .building
    private var nestTime: CGFloat = 0
    private var nestDur: CGFloat = 8
    /// Abdomen pressed to an anchor while spinning, 0..1.
    private var nestDab: CGFloat = 0
    private var nestZzzIn: CGFloat = 1
    private var wantsSleepAfterBuild = false

    // Cursor
    private var cursor = V2.zero
    private var cursorVel = V2.zero
    private var prevCursor = V2.zero
    private var pettingScore: CGFloat = 0
    private var lastPetSign: CGFloat = 0
    /// The pointer has come dashing over it, and not yet gone off it.
    private var rushed = false

    // The pointer as prey
    /// How taken it is with the pointer, 0..1: builds while the pointer
    /// hangs about close by and it has nothing better to do, and shows in
    /// the eyes, a tip of the head, a rise on its toes and a lean toward it.
    private var interest: CGFloat = 0
    private var interestNose = Spring(0, stiffness: 260, damping: 26)  // nose up (+) / down toward it
    private var interestLean = Spring(0, stiffness: 200, damping: 22)  // along the ledge toward it
    /// The yaw the pointer is asking for, in the ledge's frame; weighted by
    /// `interest` when the body is turned.
    private var interestYawTarget: CGFloat = 0
    /// The pointer's bearing as the body follows it: smoothed, and with a
    /// side it has committed to (see `updateInterest`).
    private var interestBearing: CGFloat = 1
    private var interestSide: CGFloat = 1
    /// The yaw the head and abdomen want, on the pointer: they turn to it
    /// at once and the legs come round after (see `updateHeadTurn`).
    private var headYawTarget: CGFloat = 1
    /// How much further round than the legs the head and abdomen are, as a
    /// yaw, and how fast that is changing.
    private var headTurn: CGFloat = 0
    private var headTurnVel: CGFloat = 0
    /// The most the upper body turns away from where the legs face, as a
    /// yaw: from side on, round to all but face on.
    private static let maxHeadTurn: CGFloat = 0.6
    /// Whether the look it is wearing can have its head turned round past
    /// the front view from its legs unseen (see `faceOnSymmetric`).
    private var symmetricLook: (look: SpiderLook, symmetric: Bool)?
    /// How far past the front view the pointer has to be before the legs
    /// come round to face that way, as the cosine of its bearing.
    private static let sideSwitch: CGFloat = 0.3
    /// ...and for how long, in seconds: a pointer passing back and forth
    /// over it is followed by the head and abdomen, not the legs.
    private static let sideSwitchAfter: CGFloat = 0.5
    private var sideSwitchFor: CGFloat = 0
    /// How long the head has been turned as far as it goes from the legs,
    /// wanting to go on round (see `updateHeadTurn`).
    private var headPinnedFor: CGFloat = 0
    /// How far, as a yaw, the way the legs would face following the pointer
    /// gets from the way they do before they shift round to it.
    private static let stanceShift: CGFloat = 0.3
    /// How long, in seconds, the legs stay a little way off where the
    /// pointer would have them before they settle round to it.
    private static let stanceSettle: CGFloat = 1.2
    private var stanceOffFor: CGFloat = 0
    /// The abdomen's tip on its waist: it dips as the head comes up to
    /// look at something above, and rises as it peers down.
    private var abdomenTilt = Spring(0, stiffness: 150, damping: 18)
    private var boredAfter: CGFloat = 16
    /// Fidgeting: every reversal of the pointer's direction near it counts,
    /// and the score decays. Enough of it, for long enough, and it stalks.
    private var cursorWiggle: CGFloat = 0
    private var wiggleSign = V2.zero
    private var cursorNearFor: CGFloat = 0
    private var cursorHunt: CursorHunt = .none
    private var cursorHuntSince: CGFloat = 0
    private var nextCursorHuntAt: CGFloat = 8
    private var cursorPoised = false
    private var cursorPoisedAt: CGFloat = 0
    private var cursorCentre = V2.zero
    private var cursorStalls = 0
    private var cursorStalkLastPos = V2.zero
    /// Hanging off the pointer: where it took hold, blending to a grip
    /// with its mouth on the hotspot; the body swings under it as a
    /// pendulum; shaking it back and forth wears its grip down.
    private var clingOffset0 = V2.zero
    private var clingBlend: CGFloat = 0
    private var clingSwing: CGFloat = 0
    private var clingSwingVel: CGFloat = 0
    private var clingShake: CGFloat = 0
    private var clingShakeSign = V2.zero
    private var clingSince: CGFloat = 0
    private var clingFor: CGFloat = 4
    private var cursorAcc = V2.zero
    private var prevCursorVel = V2.zero
    /// Within this (× scale) the pointer holds its interest; within the
    /// larger it may be stalked.
    static let interestRange: CGFloat = 170
    static let huntRange: CGFloat = 250

    // Commotions
    /// Where something last went off on the screen — a notification, the
    /// volume or the brightness — and until when it stays turned to it.
    private var commotionAt = V2.zero
    private var commotionUntil: CGFloat = -99
    private var commotionLast: CGFloat = -99
    private var noticing: Bool { t < commotionUntil && mode == .attached }

    // Drag
    private var grabOffset = V2.zero
    private(set) var isHeld = false

    private var legs: [Leg] = []
    private var legMode: LegMode = .free
    private var bodyWobble = Wobble(seed: 3, freq: 0.7)
    private var swayWobble = Wobble(seed: 9, freq: 1.3)

    private let gravity = Spider.gravityPull
    /// How hard it falls (and what it leaps against).
    static let gravityPull = V2(0, -1950)
    /// Body units travelled per gait cycle.
    private static let strideLength: CGFloat = 28
    /// Fraction of the cycle a leg spends in the air.
    private static let swingDuty: CGFloat = 0.34
    /// The hardest it can push off.
    static let maxJumpSpeed: CGFloat = 1250
    /// How far a corner is rounded off, in points at scale 1.
    static let cornerRadius: CGFloat = 38

    init(map: SurfaceMap) {
        self.map = map
        buildLegs()
        if let f = NSScreen.main?.frame {
            pos = V2(f.midX, f.maxY - 140)
        }
        legFramePos = pos
    }

    private func buildLegs() {
        legs = []
        for i in 0..<SpiderRenderer.legCount {
            let r = SpiderRenderer.rig(i, profile: 1, look: look)
            let near = i < 4
            let k = i % 4
            // Alternating tetrapod: near legs 1 and 3 step with far legs 2 and
            // 4, and vice versa. A few hundredths of a cycle between
            // neighbours keeps the four from moving in lockstep.
            let group = (k % 2 == 0) == near ? 0 : 1
            let phase = (group == 0 ? 0 : 0.5) + CGFloat(3 - k) * 0.03
            var leg = Leg(hip: r.hip, rest: r.foot, phase: phase)
            leg.wobble = Wobble(seed: CGFloat(i) * 2.7, freq: 1.1 + CGFloat(k) * 0.17)
            leg.foot = leg.rest
            legs.append(leg)
        }
    }

    // MARK: - External input

    func setCursor(_ p: V2) {
        cursor = p
        lastUserActivity = t
    }

    /// Where the pointer is within its reach, if not everywhere: in the
    /// habitat, the part of the tank seen through the glass — the pointer
    /// out past the glass is outside the tank. It still looks at it; it
    /// doesn't go after it. (Nil on the desktop.)
    var cursorArea: CGRect?
    private func cursorFree(_ p: V2) -> Bool { inBoxOrFree(p) && (cursorArea?.contains(p.point) ?? true) }

    var worldPos: V2 { pos }
    /// In its hammock (spinning it, getting in, asleep in it, getting out).
    var inHammock: Bool { mode == .nesting }

    var grabRadius: CGFloat { 30 * config.scale }

    func hitTest(_ p: V2) -> Bool {
        // Hanging off the pointer it is under every click: those go through.
        mode != .clinging && p.distance(to: pos) < grabRadius
    }

    func beginGrab(at p: V2) {
        tumbleVel = 0
        rappelAfterCatch = false
        pointerDrop = false
        lineOrder = nil
        pendingMap = nil
        climbArrival = nil
        abandonBuild()
        cursorHunt = .none
        departLeap = false
        if flyingHome { flyingHome = false; noAttachFor = 0 }
        isHeld = true
        mode = .held
        activity = .idle
        queued = nil
        grabOffset = pos - p
        grabbed.velocity = 6
        startled.velocity = 9
        setEmote(.surprise, 0.7)
        legMode = .free
        wake()
    }

    func moveGrab(to p: V2) {
        cursor = p
        lastUserActivity = t
    }

    func endGrab(throwVelocity v: V2) {
        guard isHeld else { return }
        isHeld = false
        grabOffset = .zero
        let speedV = v.clampedLength(2700)
        remember(speedV.length < Spider.hardThrow ? .carried : .thrown)
        if webActive {
            // Slingshot on the thread instead of flying free.
            mode = .dangling
            hangOffFresh = true
            let r = pos - webAnchor
            webLen = max(24, r.length)
            webLenTarget = webLen
            webAngle = atan2(r.x, -r.y)
            webAngleVel = speedV.dot(V2(-r.y, r.x).normalized) / max(webLen, 1)
        } else {
            mode = .airborne
            air = .thrown
            vel = speedV
            airTime = 0
            noAttachFor = 0.06
            launchLoop = ""
            // Let go of from a height it shoots a line up at the ceiling as
            // it leaves your hand and catches itself on the way down — a
            // drop or a light toss, that is; flung hard, it flies.
            if speedV.length < Spider.hardThrow { planFall(from: nil, lineUp: true) }
        }
        stretch.velocity = -4
        legMode = .free
    }

    /// Scrolled over: up is up its line, down is down it — or, on a ledge,
    /// down off it on a line. One swipe (a trackpad's, momentum and all, or
    /// a quick run of wheel clicks) is one order, however long it runs on
    /// for: `startsGesture` says whether this is the first of a new one,
    /// where the device can tell; otherwise a pause says so. `precise`: a
    /// trackpad's points rather than a wheel's lines, so an order takes a
    /// deliberate little swipe, not a brush of the fingers.
    func scroll(_ dy: CGFloat, precise: Bool = true, startsGesture: Bool? = nil) {
        lastUserActivity = t
        if startsGesture ?? (t - scrollLast > 0.35) {
            scrollSum = 0
            scrollGave = 0
        }
        scrollLast = t
        scrollSum += dy
        guard abs(scrollSum) >= (precise ? 4 : 0.5) else { return }
        let way: CGFloat = scrollSum > 0 ? 1 : -1
        // (Swiped back the other way before letting go: that is an order too.)
        guard way != scrollGave else { return }
        scrollGave = way
        obey(up: way > 0)
    }

    /// Does as the scroll wheel says (see `LineOrder`).
    private func obey(up: Bool) {
        switch mode {
        case .attached:
            // Down off the ledge on a line. (Up from a ledge is nowhere.)
            guard !up, config.webs, canRappel(userAsked: true) else { return }
            lineOrder = .drop
            orderedAt = t
            dropOnWeb()
        case .airborne where draglineCatchY != nil && webActive:
            // Stepping off on its dragline: once the line has its weight,
            // on down it goes, or back up, as told.
            lineOrder = up ? .up : .down
            orderedAt = t
        case .dangling:
            guard webActive, climbArrival == nil, !inCinema, mantle == nil else { return }
            if hangOnly, let box = confine {
                // Hanging in its box there is nowhere to go but up and down
                // the line: as far as it goes, and there it stays a while.
                webLenTarget = up ? 30 : max(30, box.height - 60)
                decisionIn = max(decisionIn, 12)
                return
            }
            if webStyle == .swing {
                // Mid-swing: it stops working the swing and does as it is
                // told, the swing dying away under it.
                webStyle = .hang
                swingPumping = false
                prevHangLen = webLen
            }
            lineOrder = up ? .up : .down
            orderedAt = t
            webPlan = [up ? .climbHome : .toFloor]
            lingerUntil = -1
            lineJoyUntil = 0
            floorWait = -1
            decisionIn = 0
            webLenTarget = up ? lineTop - 4 * config.scale : floorLen
        default:
            break
        }
    }

    /// Single click on the body: it notices you.
    func poke() {
        wake()
        lastUserActivity = t
        remember(.greeted)
        // Who it is decides how it takes being prodded.
        let love = lerp(0.3, 1.6, personality.affection)
        let jumpy = lerp(1.6, 0.25, personality.bravery)
        let options: [(CGFloat, () -> Void)] = [
            (3 * love, { self.beginActivity(.wave, dur: 1.5); self.happy.velocity = 7; self.setEmote(.sparkle, 0.8) }),
            (2 * love, { self.beginActivity(.armsUp, dur: 1.2); self.happy.velocity = 6; self.setEmote(.hearts, 1.0) }),
            (3 * love, { self.beginActivity(.greet, dur: randRange(1.8, 2.6)); self.happy.velocity = 7; self.setEmote(.hearts, 1.2) }),
            (1.5 * lerp(0.3, 1.8, self.personality.playfulness), { self.beginActivity(.drum, dur: randRange(2.9, 4.4)); self.setEmote(.note, 1.4) }),
            (2 * jumpy, { self.beginActivity(.startle, dur: 0.55); self.startled.velocity = 12; self.setEmote(.surprise, 0.6) }),
            (1.5 * lerp(0.5, 1.6, self.personality.curiosity), { self.beginActivity(.curious, dur: 1.4); self.setEmote(.question, 1.1) }),
            (1.5, { self.beginActivity(.glance, dur: 1.2) }),
            (1.5 * lerp(0.2, 1.8, self.personality.playfulness), { self.beginActivity(.wiggle, dur: 0.9); self.happy.velocity = 5 }),
            (1.0 * lerp(1.8, 0.1, self.personality.affection), {
                // The grumpy option: a stern look and it turns its back on you.
                self.beginActivity(.look, dur: 0.6)
                self.queue(.turn, 0.9)
                self.pendingDir = -self.walkDir
                // ...with a shake of the head first, now and then: no.
                if !Spider.debugNoBodyLanguage, chance(0.5) {
                    self.activityDur = 1.1
                    self.shakeHead()
                }
            }),
            // A curt nod: noted. The cooler it is with you, the likelier.
            (Spider.debugNoBodyLanguage ? 0 : 1.2 * lerp(1.4, 0.3, self.personality.affection), {
                self.beginActivity(.look, dur: 1.2)
                self.nod(times: chance(0.5) ? 1 : 2)
            }),
            // A slow blink: a fond one's answer.
            (Spider.debugNoBodyLanguage ? 0 : 1.0 * lerp(0.2, 1.4, self.personality.affection), {
                self.beginActivity(.stare, dur: randRange(1.8, 2.4))
                self.slowBlink(in: 0.5)
                self.happy.velocity = 4
            }),
        ]
        let total = options.reduce(0) { $0 + $1.0 }
        var pick = randRange(0, total)
        for (w, act) in options {
            pick -= w
            if pick <= 0 { act(); break }
        }
        stretch.velocity = -5
    }

    /// Double click: happy hop.
    // MARK: Showing a habit

    /// A habit asked for from the Studio, waiting until it can be done.
    private var pendingDemo: WritableKeyPath<Habits, CGFloat>?
    private var demoClimbs = 0
    /// Getting into place for it (turning round, backing up for room):
    /// the demo waits until that is done — or, with `demoReady`, until
    /// that says it is in place, which may be before the walk is over.
    private var demoSetUp = false
    private var demoReady: (() -> Bool)?

    /// Does what a habit dial is about, now, the way it does it of its own
    /// accord — so the Studio's ▶ next to a slider shows exactly what that
    /// slider makes more or less of. In the air or on a line it waits
    /// until it is back on something (except a swing, which it can work up
    /// from a line); something that needs height, it climbs for first.
    func demo(_ habit: WritableKeyPath<Habits, CGFloat>) {
        wake()
        lastUserActivity = t
        pendingDemo = habit
        demoClimbs = 0
        demoSetUp = false
        demoReady = nil
        runPendingDemo()
    }

    private func runPendingDemo() {
        guard let h = pendingDemo else { return }
        if demoSetUp {
            // Still getting into place. (Once it is, whatever it has taken
            // up in the meantime gives way.)
            guard mode == .attached, activity != .turn else { return }
            let there = demoReady?() ?? false
            guard there || ![.walk, .sneak, .scurry].contains(activity) else { return }
            demoSetUp = false
            demoReady = nil
        }
        if h == \.swing, mode == .dangling, config.webs {
            pendingDemo = nil
            workUpSwing()
            return
        }
        guard mode == .attached, !absorbingLanding, pendingJump == nil,
              activity != .crouch, activity != .shoot, activity != .turn else { return }
        pendingDemo = nil
        queued = nil
        walkThen = nil
        if h != \.hammock, h != \.nap { homing = nil }
        // Held for its whole length: nothing else is decided over the top.
        func hold(_ a: Activity, _ d: CGFloat) {
            beginActivity(a, dur: d)
            decisionIn = d + 1.5
        }
        switch h {
        case \.wander:
            turnTo(chance(0.5) ? walkDir : -walkDir, then: .walk, for: 2.6)
            decisionIn = 4
        case \.leap:
            // Nowhere to leap to from here (tucked under something low, say):
            // round the corner onto the side of it first.
            if let spot = bestJumpSpot(from: pos, exclude: anchor.loopID) ?? anyLeap() {
                startJump(to: spot.point)
            } else if demoClimbs < 2, walkRoundCorner(for: h, onto: { _ in true }) {
                demoClimbs += 1
            } else {
                hold(.hop, Spider.hopDur)
            }
        case \.rappel:
            if config.webs, canRappel(userAsked: true) { dropOnWeb() } else { climbFor(h) }
        case \.swing:
            guard config.webs, !confined else { hold(.look, 1.2); break }
            if startSwing() { break }
            // The line would go out behind it: round first. Nowhere to swing
            // from here at all: over to somewhere there is.
            if let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count,
               swingLine(from: pos, on: anchor.loopID, forward: loop.segs[anchor.segIdx].dir * -walkDir) != nil {
                pendingDemo = h
                demoSetUp = true
                turnTo(-walkDir, then: .idle, for: 0.1)
                decisionIn = 2
            } else {
                perchFor(h)
            }
        case \.hammock: buildHammock()
        case \.nap: napInHammock()
        case \.sleep: hold(.sleep, 6)
        case \.drum: hold(.drum, 3.4); setEmote(.note, 1.4)
        case \.dance: hold(.dance, 1.8); setEmote(.note, 1.4)
        case \.danceMusic:
            // The music it hears, or — with none on — a beat of its own.
            if music == nil {
                demoBeatFrom = t
                demoBeatUntil = t + 30
                musicNoticed = true
                grooveClock = false
                followBeat(dt: 0)
            }
            startGroove()
            groovePulses = min(groovePulses, 16)
        case \.roll:
            if let dir = rollWay() {
                if dir == walkDir { hold(.roll, 1.7); queue(.shake, 0.45) } else { turnTo(dir, then: .roll, for: 1.7); decisionIn = 4 }
            } else if !backUpToRoll(h) {
                floorFor(h)
            }
        case \.spin: hold(.spin, 0.1)
        case \.pushup: hold(.pushup, 1.6)
        case \.stretch: hold(.legStretch, 1.6)
        case \.wiggle: hold(.wiggle, 0.9)
        case \.armsUp: hold(.armsUp, 1.3)
        case \.look: hold(.look, 1.8)
        case \.rest: hold(.rest, 4)
        case \.groom: hold(.groom, 2.2)
        case \.fidget: hold(.fidget, 1.0)
        case \.scratch: hold(.scratch, 1.4)
        case \.peer: hold(.peer, 1.6)
        case \.muse:
            if design.allPhrases.isEmpty { think([.heart, .star, .music, .sun].randomElement()!) } else { thinkSomething() }
            hold(.look, 1.4)
        case \.approach:
            // Off to see the pointer — or, with the pointer off over the
            // button, to the middle of wherever it is.
            let f = map.screenFrame(containing: pos)
            let goal = f.contains(cursor.point) ? cursor : V2(f.midX, f.midY)
            walkToward(goal)
            decisionIn = activityDur + 1.5
        case \.curious: hold(.curious, 1.8); setEmote(.question, 1.2)
        case \.stare: hold(.stare, 3.5)
        case \.glance: hold(.glance, 1.2)
        case \.walkTurned:
            // Off along its edge turned round toward you, eyes on you — the
            // way it has room to go.
            turnTo(wanderWay(), then: .walk, for: 3.2)
            var c = Carriage()
            c.kind = .turned
            c.turn = randRange(0.38, 0.55)
            c.eyes = 1
            if chance(0.5) { c.cock = (chance(0.5) ? 1 : -1) * randRange(0.12, 0.2) }
            carriage = c
            carriageFor = .walk
            carriageUntil = t + 4.5
            decisionIn = 4.6
        case \.greet: hold(.greet, 2.2); happy.velocity = 5; setEmote(.hearts, 1.2)
        case \.wave: hold(.wave, 1.5); happy.velocity = 4
        case \.peekaboo:
            // The game needs a window edge in front of it to hide behind.
            // With none here (the Studio's little box has none), it shows
            // the moment the game is all about: out it bursts — boo! — and
            // is pleased with itself.
            if startPeekaboo(reach: 600) { break }
            hold(.armsUp, 1.2)
            setEmote(.surprise, 0.9)
            happy.velocity = 6
            startled.velocity = 3
            stretch.velocity = 4
            queue(.wiggle, 1.0)
        default: hold(.look, 1.2)
        }
    }

    /// A line needs height under it: up to the highest place in reach
    /// first, and then the line, on arriving.
    private func climbFor(_ habit: WritableKeyPath<Habits, CGFloat>) {
        guard demoClimbs < 2 else { beginActivity(.look, dur: 1.2); return }
        demoClimbs += 1
        let spots = map.sampleSpots(spacing: 30).filter { $0.loop.id != anchor.loopID || $0.point.y > pos.y + 60 }
        guard let high = spots.max(by: { $0.point.y < $1.point.y }), high.point.y > pos.y + 40 else {
            beginActivity(.look, dur: 1.2)
            return
        }
        pendingDemo = habit
        startJump(to: high.point)
    }

    /// Down onto something it can stand on top of, to show off what can
    /// only be done there (a roll): the nearest stretch of floor with room.
    private func floorFor(_ habit: WritableKeyPath<Habits, CGFloat>) {
        guard demoClimbs < 2 else { beginActivity(.look, dur: 1.2); return }
        demoClimbs += 1
        // Up the side of a window to its top, or down a wall of the screen to
        // the floor: round the corner on foot, rather than leap for it.
        let long = rollDistance + 12 * config.scale
        if walkRoundCorner(for: habit, onto: { $0.normal.y > Spider.rollFloor && $0.len > long }) { return }
        // Somewhere along the middle of it, not by an end — land by a
        // corner and it may well come down on the side — and it backs up
        // for the room from there (see `backUpToRoll`).
        let room = rollDistance + 12 * config.scale
        let clear = 40 * config.scale
        let spots = map.sampleSpots(spacing: 30).filter { s in
            s.seg.normal.y > Spider.rollFloor && s.seg.len > room && s.anchor.t > clear && s.anchor.t < s.seg.len - clear
                && inBoxOrFree(s.point) && s.point.distance(to: pos) > 40 * config.scale && ballistic(from: pos, to: s.point) != nil
        }
        guard let floor = spots.min(by: { $0.point.distance(to: pos) < $1.point.distance(to: pos) }) else {
            beginActivity(.look, dur: 1.2)
            return
        }
        pendingDemo = habit
        startJump(to: floor.point)
    }

    // MARK: Rolling
    //
    // A roll is a ball going along the ground: it can only be done on top
    // of something. Under a window, or up the side of one, the ball would
    // just drop off — so it never starts one there, and never one that would
    // carry it round a corner onto a side or an underside.

    /// How upward a ledge has to face to roll on.
    private static let rollFloor: CGFloat = 0.7
    /// About how far a roll carries it — the one turn of the ball, and the
    /// push into it and the slide out of it (about 116 all told at scale 1)
    /// — with a little to spare.
    private var rollDistance: CGFloat {
        (2 * .pi - Spider.rollTip) * (Spider.ballAlong + Spider.ballAcross) / 2 * config.scale * 1.2
    }

    /// On a floor long enough to roll on, but too near the end of it either
    /// way: back along it far enough to have the room. False if this floor
    /// is too short for a roll at all.
    private func backUpToRoll(_ habit: WritableKeyPath<Habits, CGFloat>) -> Bool {
        guard demoClimbs < 3, mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return false }
        let seg = loop.segs[anchor.segIdx]
        let room = rollDistance
        let slack = 12 * config.scale
        guard seg.normal.y > Spider.rollFloor, seg.len > room + slack else { return false }
        // The nearer of: far enough back to roll forward along it, or far
        // enough along to roll back.
        let forwardFrom = seg.len - room - slack    // at or before this, a roll toward +dir fits
        let backFrom = room + slack                 // at or after this, a roll toward -dir fits
        let goal = abs(anchor.t - forwardFrom) < abs(anchor.t - backFrom) ? min(anchor.t, forwardFrom) : max(anchor.t, backFrom)
        let dist = abs(goal - anchor.t)
        guard dist > 1 else { return false }
        demoClimbs += 1
        pendingDemo = habit
        demoSetUp = true
        demoReady = { [unowned self] in rollWay() != nil }
        // Plenty of time: it stops as soon as there is room (`demoReady`).
        let walk = (dist + slack) * 2 / max(config.walkSpeed, 1) + 0.5
        turnTo(goal > anchor.t ? 1 : -1, then: .walk, for: walk)
        walkThen = nil
        decisionIn = walk + 2
        return true
    }

    /// Any leap at all, for showing one off where `bestJumpSpot` finds none
    /// worth making (a cramped spot, the Studio's little box): somewhere on
    /// another edge it can reach without jumping through what it is on.
    private func anyLeap() -> (anchor: Anchor, point: V2)? {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return nil }
        let normal = loop.segs[anchor.segIdx].normal
        let sc = config.scale
        let ok = map.sampleSpots(spacing: 30).filter { s in
            let d = s.point.distance(to: pos)
            guard d > 45 * sc, d < 680, s.loop.id != anchor.loopID || s.anchor.segIdx != anchor.segIdx, inBoxOrFree(s.point),
                  let launch = ballistic(from: pos, to: s.point) else { return false }
            return launch.normalized.dot(normal) > 0.05
        }
        return ok.randomElement().map { ($0.anchor, $0.point) }
    }

    /// Round the nearest corner of what it is on onto the next edge, if that
    /// edge is `onto` and nothing is in the way — then on with the demo.
    private func walkRoundCorner(for habit: WritableKeyPath<Habits, CGFloat>, onto: @escaping (Seg) -> Bool) -> Bool {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return false }
        let n = loop.segs.count
        let seg = loop.segs[anchor.segIdx]
        var best: (dir: CGFloat, dist: CGFloat)?
        for dir in [CGFloat(1), -1] {
            let idx = anchor.segIdx + (dir > 0 ? 1 : -1)
            guard loop.closed || (idx >= 0 && idx < n), onto(loop.segs[(idx + n) % n]) else { continue }
            // Clear all the way to the corner.
            let lim = seg.limit(from: anchor.t, dir: dir)
            guard dir > 0 ? lim >= seg.len - 0.01 : lim <= 0.01 else { continue }
            let dist = dir > 0 ? seg.len - anchor.t : anchor.t
            if best == nil || dist < best!.dist { best = (dir, dist) }
        }
        guard let b = best else { return false }
        pendingDemo = habit
        demoSetUp = true
        let from = anchor.segIdx
        let inFrom = 24 * config.scale
        demoReady = { [unowned self] in
            guard anchor.loopID == loop.id, anchor.segIdx != from, anchor.segIdx < loop.segs.count else { return false }
            let seg = loop.segs[anchor.segIdx]
            return onto(seg) && anchor.t > inFrom && anchor.t < seg.len - inFrom
        }
        let walk = (b.dist + 30 * config.scale) * 2 / max(config.walkSpeed, 1) + 0.5
        turnTo(b.dir, then: .walk, for: walk)
        walkThen = nil
        decisionIn = walk + 2
        return true
    }

    /// Somewhere to swing from, for showing it off: the nearest spot it can
    /// leap to with a line to shoot out one way or the other.
    private func perchFor(_ habit: WritableKeyPath<Habits, CGFloat>) {
        // (A leap in a cramped spot can come down somewhere else: a few goes.)
        guard demoClimbs < 3 else { beginActivity(.look, dur: 1.2); return }
        demoClimbs += 1
        let near = map.sampleSpots(spacing: 30)
            .filter { $0.loop.id != anchor.loopID || $0.anchor.segIdx != anchor.segIdx || $0.point.distance(to: pos) > 60 * config.scale }
            .filter { inBoxOrFree($0.point) && $0.point.distance(to: pos) > 40 * config.scale }
            .sorted { $0.point.distance(to: pos) < $1.point.distance(to: pos) }
        for s in near.prefix(80) where ballistic(from: pos, to: s.point) != nil {
            if swingLine(from: s.point, on: s.loop.id, forward: s.seg.dir) != nil
                || swingLine(from: s.point, on: s.loop.id, forward: -s.seg.dir) != nil {
                pendingDemo = habit
                startJump(to: s.point)
                return
            }
        }
        beginActivity(.look, dur: 1.2)
    }

    /// Whether a roll the way of `dir` stays on top of things the whole way.
    private func canRoll(toward dir: CGFloat) -> Bool {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return false }
        let seg = loop.segs[anchor.segIdx]
        guard seg.normal.y > Spider.rollFloor else { return false }
        // Room enough before the end of this ledge — or, past it, more floor
        // to roll on (or the end of the line, where it stops).
        let room = dir > 0 ? seg.len - anchor.t : anchor.t
        if room > rollDistance { return true }
        let n = loop.segs.count
        let nextIdx = anchor.segIdx + (dir > 0 ? 1 : -1)
        guard loop.closed || (nextIdx >= 0 && nextIdx < n) else { return true }
        return loop.segs[(nextIdx + n) % n].normal.y > Spider.rollFloor
    }

    /// Which way it can roll from here — the way it is facing if it can —
    /// or nil if it cannot roll here at all.
    private func rollWay() -> CGFloat? {
        canRoll(toward: walkDir) ? walkDir : canRoll(toward: -walkDir) ? -walkDir : nil
    }

    func celebrate() {
        wake()
        remember(.greeted)
        happy.velocity = 10
        setEmote(.hearts, 1.3)
        if mode == .dangling, webStyle == .hang {
            // Pleased, on a line: a bounce on the end of it, and a happy
            // kick of the legs hanging free.
            lineJoyUntil = t + randRange(1.2, 1.8)
            bungee.velocity = randRange(140, 200)
            setEmote(.sparkle, 1.2)
        }
        if mode == .attached {
            if chance(lerp(0.8, 0.3, personality.playfulness)) {
                beginActivity(.bounce, dur: 1.0)
                queue(.wiggle, 0.9)
            } else {
                beginActivity(.dance, dur: 1.6)
                queue(.armsUp, 0.9)
            }
        }
    }

    // MARK: Locked away

    /// Put to bed while the Mac is locked or asleep, so that the first thing
    /// you see when you come back is it fast asleep: curled up in its
    /// hammock if it has one, or on the top of a window or the floor of the
    /// screen you are on. It stays asleep, however long, until
    /// `wakeAndGreet()`.
    private(set) var dormant = false
    /// Once it is up: straight over to say hello.
    private var greetOnWaking = false
    /// How likely it is to be in its hammock, if it has one, when you are
    /// back.
    static let hammockWhenAway: CGFloat = 0.75

    func tuckIn(near: V2) {
        wake()
        dormant = true
        greetOnWaking = false
        departing = nil
        laser = nil
        cursorHunt = .none
        homing = nil
        bedBoundUntil = -1
        abandonBuild()
        // The hammock, if there is one — most times, not every time (now
        // and then it nods off wherever it is), unless it is in it already
        // — and it stays in it: its weight sags the sling, which may take
        // the bed down behind a window.
        if let h = hammock, h.progress >= 1, config.hammocks, !inHabitat, confine == nil,
           map.isVisible(nestCentre(h), depth: Int.max),
           mode == .nesting && nestPhase == .sleeping || chance(Spider.hammockWhenAway) {
            if mode != .nesting || nestPhase != .sleeping {
                teleport(to: nestCentre(h))
                hammock = h
                mode = .nesting
                nestPhase = .sleeping
                nestWalking = false
                legMode = .free
                nestZzzIn = 0
                shiftIn = randRange(6, 14)
            }
            nestTime = 0
            nestDur = .greatestFiniteMagnitude
            settleAsleep()
            if mode == .nesting { return }
        }
        // Otherwise on a ledge in sight: the top of a window for choice.
        let screen = confine ?? map.screenFrame(containing: near)
        var best: (score: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) where spot.seg.facing == .up && screen.contains(spot.point.point) {
            guard spot.seg.isOpen(at: spot.anchor.t), spot.loop.kind == .windowEdge || spot.loop.kind == .screenBorder else { continue }
            // Somewhere it will be seen: the middle of things rather
            // than off in a corner.
            let off = abs(spot.point.x - screen.midX) / max(screen.width / 2, 1)
            let score = (spot.loop.kind == .windowEdge ? 1.3 : 1) * (1.2 - off * 0.7) * appeal(spot.point, on: spot.loop.kind) * randRange(0.8, 1.2)
            if best == nil || score > best!.score { best = (score, spot.point) }
        }
        let bed = best?.point ?? V2(screen.midX, screen.minY + map.standoff)
        teleport(to: bed + V2(0, 14 * config.scale))
        setEmote(.none, 0)
        startled.reset(0)
        // Down onto the bed, out of sight, before it is seen.
        for _ in 0..<150 where mode != .attached { update(dt: 1.0 / 60.0) }
        fallAsleep()
        settleAsleep()
    }

    /// Asleep where it stands, for as long as it is dormant.
    private func fallAsleep() {
        guard mode == .attached else { return }
        beginActivity(.sleep, dur: .greatestFiniteMagnitude)
        // The Z's fade on their own span, held half through while it sleeps.
        setEmote(.zzz, 4)
    }

    /// Eyes shut, and a moment, out of sight, for the legs to fold up.
    private func settleAsleep() {
        sleepiness.reset(1)
        lid.reset(1)
        happy.reset(0)
        for _ in 0..<90 { update(dt: 1.0 / 60.0) }
    }

    var debugHammockBed: String {
        guard let h = hammock else { return "no hammock" }
        return "progress \(h.progress) hammocks \(config.hammocks) confine \(confine != nil) bed \(Int(nestCentre(h).x)),\(Int(nestCentre(h).y)) visible \(map.isVisible(nestCentre(h), depth: Int.max))"
    }

    /// Asleep where it can be seen: not under a window that has come over it.
    var bedInSight: Bool {
        switch mode {
        case .nesting: return map.isVisible(pos, depth: Int.max)
        case .attached:
            guard let loop = map.loop(anchor.loopID) else { return false }
            guard loop.kind.onWindow else { return true }
            return (map.seg(anchor).map { $0.isOpen(at: anchor.t) } ?? false) && map.isVisible(pos, depth: loop.depth)
        default: return false
        }
    }

    /// You are back: it wakes — a stretch, a shake — and comes to say hello.
    func wakeAndGreet() {
        guard dormant else { return }
        dormant = false
        greetOnWaking = true
        remember(.greeted, 0.5)
        if mode == .nesting {
            nestDur = 0   // up and out along the silk; a stretch on the wall
            return
        }
        guard mode == .attached else { return }
        if activity == .sleep {
            wokeUp = false
            beginActivity(.stretch, dur: 1.5)
            queue(.shake, 0.55)
            sleepiness.velocity = -2
            lastUserActivity = t
        }
    }

    private func greetYou() {
        greetOnWaking = false
        // A cool one: oh, it's you — a look, and a nod.
        if !Spider.debugNoBodyLanguage, personality.affection < 0.3, chance(0.7) {
            beginActivity(.stare, dur: 1.6)
            nod(times: 1)
            decisionIn = randRange(1.5, 3)
            return
        }
        happy.velocity = 8
        setEmote(.hearts, 1.6)
        beginActivity(.greet, dur: 2.6)
        queue(.wave, 1.5)
        decisionIn = randRange(1.5, 3)
    }

    /// The charger has gone in: a jolt of excitement, even out of a nap,
    /// crackling with it. Stood on top of something, it jumps for joy — a
    /// real jump, gathering itself, up off its legs and down onto them
    /// again; on a wall or under a ledge every foot stays where it is, and
    /// it bobs and wiggles on them.
    func perkUp() {
        guard !config.paused, !dormant, !inCinema, !isHeld, activity != .eat else { return }
        happy.velocity = 9
        setEmote(.charge, 1.6)
        joyLeapFrom = -1
        joyLanding = false
        // Gathered for a leap, or in the middle of one of its moves, it
        // only crackles: it does not drop what it is doing.
        guard mode == .attached, pendingJump == nil,
              ![.crouch, .shoot, .turn, .fasten, .roll, .spin].contains(activity) else { return }
        wake()
        let free = laser == nil && huntTarget == nil && caught == nil && build == nil
            && peek == nil && cursorHunt == .none && departing == nil
            && friendChase == nil && friendFlee == nil
        if surfaceNormal.y > 0.85, free {
            queued = nil
            walkThen = nil
            beginActivity(.hop, dur: Spider.hopDur + 0.1)
            joyLeapFrom = activityStarted
            decisionIn = max(decisionIn, 1.2)
            return
        }
        beginActivity(.bounce, dur: 1.0)
        queue(.wiggle, 0.9)
    }

    /// A joy leap on its way: the `.hop` begun then gathers and pushes off
    /// as any hop does, and at the top of the push leaves the ledge for real
    /// (see `leapForJoy`). The hop's start time, or -1.
    private var joyLeapFrom: CGFloat = -1
    /// Up in a joy leap: a happy wiggle once it is down.
    private var joyLanding = false

    /// Straight up off the ledge under gravity, as high as its legs throw
    /// it, and down again where it stood.
    private func leapForJoy() {
        joyLeapFrom = -1
        let sc = config.scale
        let g = -gravity.y
        let height = randRange(36, 50) * sc * lerp(0.85, 1.2, personality.playfulness)
        let vy = (2 * g * height).squareRoot()
        mode = .airborne
        air = .jump
        airTime = 0
        vel = V2(0, vy)
        // Not caught by the ledge it is leaving on the way up.
        noAttachFor = vy / g
        launchLoop = ""
        if let spot = map.nearestSpot(to: anchorPos, within: 12 * sc) { landing = (spot.point, spot.seg.angle, spot.seg.dir) }
        crouch.velocity = -9
        stretch.velocity = 6
        wag.reset(0)
        legMode = .free
        joyLanding = true
    }

    /// Something went off up on the screen. A notification sliding in is a
    /// fright (`fright`): it jumps — right up off whatever it is standing
    /// on, if it is on top of something — and stares at where it happened.
    /// The volume or the brightness changing only makes it turn and look.
    /// A run of them (a key held down) is all one: the rest only keep its
    /// eyes there a while longer.
    func noticeCommotion(at p: V2, fright: Bool) {
        guard !config.paused, !dormant, !inCinema else { return }
        let fresh = t - commotionLast > 2.5
        commotionLast = t
        let jumpy = lerp(1.35, 0.6, personality.bravery)
        // Busy with something that matters more — a hunt, the laser, a
        // meal, you — it only flinches; asleep, only a fright wakes it.
        let settled = mode == .attached && !isHeld && laser == nil && huntTarget == nil && caught == nil
            && build == nil && peek == nil && cursorHunt == .none && departing == nil && pendingJump == nil
            && friendChase == nil && friendFlee == nil && (fright || activity != .sleep)
            && ![.eat, .crouch, .shoot, .turn, .fasten, .roll, .spin].contains(activity)
        if settled {
            commotionAt = p
            let look = fright ? randRange(2.0, 3.0) : randRange(1.4, 2.2)
            commotionUntil = max(commotionUntil, t + look * lerp(0.8, 1.3, personality.curiosity))
        }
        guard fresh else {
            if fright { startled.velocity = max(startled.velocity, 3 * jumpy) }
            if activity == .look, t < commotionUntil { activityDur = max(activityDur, activityTime + commotionUntil - t) }
            return
        }
        guard fright else {
            guard settled, distractable || activity == .rest else { return }
            wake()
            queued = nil
            walkThen = nil
            beginActivity(.look, dur: commotionUntil - t)
            decisionIn = max(decisionIn, commotionUntil - t)
            return
        }
        startled.velocity = 11 * jumpy
        setEmote(.surprise, 0.8)
        remember(.startled)
        noteFright(from: p)
        guard settled else { return }
        wake()
        queued = nil
        walkThen = nil
        decisionIn = max(decisionIn, commotionUntil - t)
        if surfaceNormal.y > 0.85 {
            startleHop(awayFrom: p)
        } else {
            beginActivity(.startle, dur: 0.55)
            queue(.look, max(commotionUntil - t - 0.55, 0.8))
        }
    }

    /// Stood on top of something: a fright sends it straight up off it —
    /// no crouch first, it is a flinch — and down again where it was, or a
    /// little back from where the fright came from if the ledge goes on
    /// that way. (It looks on once it lands: see `land`.)
    private func startleHop(awayFrom p: V2) {
        let sc = config.scale
        let g = -gravity.y
        let height = randRange(42, 56) * sc * lerp(1.2, 0.85, personality.bravery)
        let vy = (2 * g * height).squareRoot()
        let flight = 2 * vy / g
        var back = (pos.x < p.x ? -1 : 1) * randRange(8, 20) * sc
        var spot = map.nearestSpot(to: anchorPos + V2(back, 0), within: 6 * sc)
        if spot == nil {
            back = 0
            spot = map.nearestSpot(to: anchorPos, within: 12 * sc)
        }
        mode = .airborne
        air = .jump
        airTime = 0
        vel = V2(back / flight, vy)
        // Not caught by the ledge it is leaving on the way up.
        noAttachFor = vy / g
        launchLoop = ""
        if let spot { landing = (spot.point, spot.seg.angle, spot.seg.dir) }
        crouch.velocity = -9
        stretch.velocity = 6
        wag.reset(0)
        legMode = .free
    }

    /// Menu command: walk / jump toward a point.
    func summon(to p: V2, door: Bool = false) {
        wake()
        // Called: whatever it was looking into can wait a while. (Through a
        // door it opened on its way somewhere, it is still on its way.)
        if !door, errand != nil { endErrand(how: 0) }
        if inquiry != nil { endInquiry() }
        freshlyNoticed = nil
        inquiryRestUntil = max(inquiryRestUntil, t + 20)
        if let spot = map.nearestSpot(to: p, within: 260) {
            if mode == .attached, spot.anchor.loopID == anchor.loopID {
                walkToward(p)
            } else if mode == .attached {
                startJump(to: spot.point)
            }
        } else if mode == .attached {
            walkToward(p)
        }
        happy.velocity = 5
    }

    /// Called when it is shown again after being hidden.
    func reappear() {
        wake()
        if mode == .attached {
            // The desktop has gone on without it while it was away: it
            // takes its footing again from wherever it is standing, and if
            // that is gone, it drops from there.
            surfacesRestructured()
        }
        if mode == .attached {
            beginActivity(.shake, dur: 0.6)
            queue(.look, randRange(0.8, 1.5))
        }
        setEmote(.sparkle, 0.9)
    }

    /// Dress it and shape its character. Safe to call every time a studio
    /// slider moves: the legs keep their current positions and only their
    /// rest shape changes.
    func apply(design d: SpiderDesign) {
        let legsChanged = d.look.legs != look.legs
        look = d.look
        name = d.name
        basePersonality = d.personality
        refreshTemperament(force: true)
        gait = d.gait
        habits = d.habits
        packs = d.packs
        customPhrases = d.customPhrases
        config.walkSpeed = 62 * gait.speedMul
        if legsChanged {
            for i in 0..<legs.count {
                let r = SpiderRenderer.rig(i, profile: 1, look: look)
                legs[i].hip = r.hip
                legs[i].rest = r.foot
            }
        }
    }

    var design: SpiderDesign {
        SpiderDesign(name: name, look: look, personality: basePersonality, gait: gait, habits: habits, packs: packs, customPhrases: customPhrases)
    }

    // MARK: Memory

    /// The Studio's personality, as its memories shift it.
    private func refreshTemperament(force: Bool = false) {
        learned = memory?.shift ?? .zero
        let p = basePersonality.shifted(by: learned)
        if force || p != personality { personality = p }
    }

    /// Something worth remembering happened, here.
    private func remember(_ e: Experience, _ amount: CGFloat = 1) {
        memory?.record(e, amount, at: placeHere())
        // (And for a while after, it goes about it in that frame of mind:
        // see `moodGlow`.)
        switch e {
        case .fed, .huntWon, .played, .petted: lastGlow = t
        case .thrown, .startled, .chased: lastShaken = t
        default: break
        }
    }

    /// Where it is, as its memory thinks of places; nil in mid-air.
    private func placeHere() -> Place? {
        switch mode {
        case .attached:
            guard let loop = map.loop(anchor.loopID) else { return nil }
            return place(pos, on: loop.kind)
        case .nesting: return place(pos, on: .screenBorder)
        default: return nil
        }
    }

    private func place(_ p: V2, on kind: SurfaceKind) -> Place {
        Place(at: p, in: map.screenFrame(containing: p), on: kind, habitat: inHabitat)
    }

    /// How much its memories make it like a spot, as a multiplier (1 with
    /// no memory, or nowhere it has feelings about).
    private func appeal(_ p: V2, on kind: SurfaceKind) -> CGFloat {
        memory?.appeal(of: place(p, on: kind)) ?? 1
    }

    /// A second or so of its life, as its memory sees it.
    private func liveMemory(dt: CGFloat) {
        guard let m = memory else { return }
        memoryDue += dt
        guard memoryDue >= 1 else { return }
        var now = Moment()
        let idle = t - lastUserActivity
        now.company = !dormant && !isHeld && idle < 20 && cursor.distance(to: pos) < 300 * config.scale && cursorVel.length < 600
        now.alone = !dormant && idle > 180
        // (Put to bed while the Mac is locked is not settling on a spot:
        // a night of it would make wherever it was tucked in a favourite.)
        now.calm = !dormant && ((mode == .attached && [.rest, .sleep, .groom, .eat, .watch, .stare].contains(activity))
            || (mode == .nesting && nestPhase == .sleeping))
        now.place = placeHere()
        m.live(for: TimeInterval(memoryDue), now, base: basePersonality)
        memoryDue = 0
        refreshTemperament()
    }

    // MARK: - Frame update

    func update(dt rawDt: CGFloat) {
        guard !config.paused else { return }
        let dt = min(rawDt, 1.0 / 30.0)
        t += dt
        // A change of coat is a slow fade, over a second or two, never a flash.
        shownSurroundings = shownSurroundings.mix(surroundings, 1 - exp(-dt * 1.2))

        trackCursorMotion(dt: dt)
        updateInterest(dt: dt)
        updateBodyLanguage(dt: dt)
        updateEmote(dt: dt)
        updateBlink(dt: dt)
        liveMemory(dt: dt)
        followBeat(dt: dt)

        if mode != .airborne { landing = nil; landingReach = 0 }
        if mode != .attached { runNose = approach(runNose, 0, 8, dt); surfacePrev = nil }
        // (Going over the top is something done on its line: picked up off
        // it, say, that is the end of it.)
        if mode != .dangling { mantle = nil; entrance = nil }
        keepHung(dt: dt)
        if pendingDemo != nil { runPendingDemo() }
        switch mode {
        case .attached: updateAttached(dt: dt)
        case .airborne: updateAirborne(dt: dt)
        case .dangling: updateDangling(dt: dt)
        case .held:     updateHeld(dt: dt)
        case .nesting:  updateNesting(dt: dt)
        case .clinging: updateClinging(dt: dt)
        }

        // Heading spring, on the shortest way round. Before the legs, so a
        // planted foot can hold its place against this frame's turn rather
        // than being drawn swung round with the body and put right a frame
        // late.
        let err = angleDelta(heading, headingTarget)
        // Turning round on a thread is a slow, deliberate roll rather than
        // the snap of a landing.
        var soft: CGFloat = mode == .dangling ? (webStyle == .hang ? 0.4 : 0.5) : 1
        // Just landed: it swings down onto the surface over a few frames
        // rather than snapping square to it.
        if mode == .attached, t - landedAt < 0.4 { soft = 0.55 }
        headingVel += (err * 190 * soft - headingVel * 21 * soft.squareRoot()) * dt
        heading += headingVel * dt

        // (Its own carriage and the rest of its body language give way to
        // the pointer, which has its head and tail when it is taken with it.)
        let own = 1 - interest
        headTilt.step(to: mode == .attached && activity == .watch ? 0.72
                      : (mode == .attached ? interestNose.value * 0.85 + (worn.nod + beatNod) * own + nodNow : 0), dt: dt)
        abdomenTilt.step(to: mode == .attached ? interestNose.value * 0.7 + (worn.tail + beatTail) * own : 0, dt: dt)
        updateWeb(dt: dt)
        updatePrey(dt: dt)
        updateToys(dt: dt)
        senseTank(dt: dt)
        tidyAbandonedHammock()
        if var h = hammock, h.tickDrape(dt: dt) { hammock = h }
        rockHammock(dt: dt)
        updateLook(dt: dt)
        updateWeather(dt: dt)
        // On a line the feet hold the silk where it really lies this frame,
        // so the line goes first. (It is always side on there, so nothing
        // later this frame moves its spinnerets.)
        let ropeFirst = onLine
        if ropeFirst { updateRope(dt: dt) }
        updateLegs(dt: dt)

        // Rest the pointer on it for a moment and it tells you its name.
        let hovering = cursor.distance(to: pos) < grabRadius * 1.15 && cursorVel.length < 30 && !isHeld && mode != .clinging
        hoverFor = hovering ? hoverFor + dt : 0
        nameTag.step(to: hoverFor > 0.7 || isHeld ? 1 : 0, dt: dt)
        odometer += speed * dt / max(config.scale, 0.05)

        if activity != .roll { rollSpin = 0 }
        // Rolling, it balls up: folds at the waist on the push off, and
        // unfolds as it comes up onto its feet. (Not a squash: a squash is
        // in the ledge's frame, and would thin the ball as it turned.)
        let ballTarget: CGFloat = {
            guard activity == .roll, mode == .attached else { return 0 }
            let r = rollPhase()
            switch r.phase {
            case 0: return smoothstep(clamp((r.v - 0.4) / 0.6, 0, 1))
            case 1: return 1
            default: return 1 - smoothstep(min(r.v / 0.55, 1))
            }
        }()
        ball = approach(ball, ballTarget, 30, dt)
        let curled = mode == .nesting && nestPhase == .sleeping
        stretch.step(to: curled ? 0.86 : 1, dt: dt)
        fatten.step(to: 1, dt: dt)
        happy.step(to: 0, dt: dt)
        startled.step(to: 0, dt: dt)
        grabbed.step(to: isHeld ? 1 : 0, dt: dt)
        updateYaw(dt: dt)
        updateHeadTurn(dt: dt)
        grounded.step(to: mode == .attached ? 1 : 0, dt: dt)
        bungee.step(to: 0, dt: dt)
        webAlpha.step(to: (webActive || buildThreadFrom != nil) ? 1 : 0, dt: dt)
        wagPhase += dt * (6 + wag.value * 4)

        // Volume preservation: fattening follows stretch inversely — except
        // balled up for a roll, where it pulls in all round.
        let s = stretch.value
        fatten.value = lerp(fatten.value, curled ? 1.0 : 1 / max(0.6, s), 0.35)

        if !ropeFirst { updateRope(dt: dt) }
        updateKnees(dt: dt)
        syncTraces(dt: dt)
    }

    // MARK: The laser dot

    /// A red dot to chase. Set while the pointer is down in laser mode.
    var laser: V2? {
        didSet {
            if laser != nil, oldValue == nil {
                endToyPlay(bored: false)
                wake()
                lastUserActivity = t
                if mode == .attached { queued = nil; decisionIn = min(decisionIn, 0.15) }
            }
            if laser == nil, oldValue != nil, mode == .attached {
                // Gone: where did it go?
                beginActivity(.look, dur: randRange(1.0, 1.8))
                setEmote(.question, 1.2)
                queued = nil
            }
        }
    }
    private var lastLaserPounce: CGFloat = -9

    /// Races after the dot: along its own edge if the dot is near it, else
    /// a leap to the nearest spot to it; on it, it pounces and pats at it.
    private func chaseLaser(_ dot: V2) {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        decisionIn = randRange(0.2, 0.5)
        let seg = loop.segs[anchor.segIdx]
        let d = dot - pos
        let along = d.dot(seg.dir)
        let off = abs(d.dot(seg.normal))
        let sc = config.scale
        if d.length < 22 * sc {
            // Got it! Pats at it, then pounces on the spot.
            if t - lastLaserPounce > 1.2 {
                lastLaserPounce = t
                remember(.played, 0.25)
                if chance(0.5) { beginActivity(.hop, dur: Spider.hopDur) } else { beginActivity(.peer, dur: chance(0.5) ? 0.42 : 0.8) }
                if chance(0.4) { setEmote(.sparkle, 0.7) }
            } else {
                beginActivity(.curious, dur: randRange(0.4, 0.8))
            }
            return
        }
        if off < 40 * sc || (abs(along) > off * 2 && abs(along) < 260 * sc) {
            // Near this edge: run for it.
            let dir: CGFloat = along >= 0 ? 1 : -1
            setOff(dir)
            beginActivity(.scurry, dur: clamp(abs(along) / max(config.walkSpeed * 2.6, 1), 0.3, 2.0))
            return
        }
        // Off its edge: leap to whatever is nearest the dot.
        var best: (d: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) {
            let dd = spot.point.distance(to: dot)
            guard dd < d.length - 20, spot.point.distance(to: pos) > 40 else { continue }
            guard let launch = ballistic(from: pos, to: spot.point), launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
            if best == nil || dd < best!.d { best = (dd, spot.point) }
        }
        if let b = best {
            startJump(to: b.point)
        } else {
            let dir: CGFloat = along >= 0 ? 1 : -1
            setOff(dir)
            beginActivity(.scurry, dur: randRange(0.5, 1.2))
        }
    }

    /// Off along the ledge the way `dir` says. Going back the way it came
    /// starts from a standstill, its feet coming down where they are: it
    /// cannot turn round at a run in the space of a frame.
    private func setOff(_ dir: CGFloat) {
        guard dir != walkDir else { return }
        walkDir = dir
        facing = dir
        speed = 0
    }

    // MARK: Friends
    //
    // With visitors out on the desktop, a `Playground` runs their games
    // and tells each spider what it is up to: chasing a friend (much as it
    // chases the laser dot), running from one, or a one-off — a hello, a
    // dance, a start.

    /// Where the friend it is chasing is, in a game of tag.
    var friendChase: V2? {
        didSet {
            guard (friendChase == nil) != (oldValue == nil) else { return }
            if friendChase != nil { startPlaying() } else { fleeCornered = false }
        }
    }
    /// Where the friend it is running from is.
    var friendFlee: V2? {
        didSet {
            guard (friendFlee == nil) != (oldValue == nil) else { return }
            if friendFlee != nil { startPlaying() } else { fleeCornered = false }
        }
    }
    /// Ran out of ledge while running away: next time it leaps.
    private var fleeCornered = false

    private func startPlaying() {
        endToyPlay(bored: false)
        wake()
        if mode == .attached { queued = nil; walkThen = nil; decisionIn = min(decisionIn, 0.15) }
    }

    /// Free for a game: on something, awake, and not busy with anything
    /// that matters more — a hunt, the laser, its hammock, a film, you.
    var canPlay: Bool {
        mode == .attached && !config.paused && departing == nil && !inCinema && laser == nil && huntTarget == nil && caught == nil
            && homing == nil && build == nil && peek == nil && cursorHunt == .none && t > escapeUntil
            && !(confined && !inBox) && !hangOnly && pendingJump == nil && !absorbingLanding
            && ![.sleep, .eat, .crouch, .shoot, .turn, .roll, .spin, .peekaboo].contains(activity)
    }

    private func chaseFriend(_ p: V2) {
        chaseLaser(p)
        // Quicker to re-aim than for the dot: a friend runs.
        decisionIn = min(decisionIn, randRange(0.2, 0.4))
    }

    /// Runs from the one who is it: along its edge away from them, and a
    /// leap somewhere further off when cornered or when they get close.
    private func fleeFriend(_ p: V2) {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        decisionIn = randRange(0.3, 0.6)
        let sc = config.scale
        let d = pos - p
        if d.length > 380 * sc, !fleeCornered {
            // Well clear: a cheeky wiggle, looking back.
            beginActivity(chance(0.5) ? .wiggle : .look, dur: randRange(0.5, 0.9))
            return
        }
        if fleeCornered || (d.length < 110 * sc && chance(0.4)) {
            fleeCornered = false
            var best: (score: CGFloat, point: V2)?
            for spot in map.sampleSpots(spacing: 40) where inBoxOrFree(spot.point) {
                let hop = spot.point.distance(to: pos)
                guard hop > 60 * sc, hop < 520, spot.loop.id != anchor.loopID || hop > 200 * sc else { continue }
                let away = spot.point.distance(to: p)
                guard away > d.length + 40 else { continue }
                guard let launch = ballistic(from: pos, to: spot.point), launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
                let score = away + randRange(0, 120)
                if best == nil || score > best!.score { best = (score, spot.point) }
            }
            if let b = best { startJump(to: b.point); return }
        }
        let seg = loop.segs[anchor.segIdx]
        let along = d.dot(seg.dir)
        let dir: CGFloat = abs(along) < 4 ? (chance(0.5) ? 1 : -1) : (along >= 0 ? 1 : -1)
        setOff(dir)
        beginActivity(.scurry, dur: randRange(0.5, 1.1))
    }

    /// Hello to a friend close by: it turns their way and puts both front
    /// legs up.
    func greetFriend(at p: V2) {
        guard canPlay, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        wake()
        queued = nil
        walkThen = nil
        let dir: CGFloat = (p - pos).dot(loop.segs[anchor.segIdx].dir) >= 0 ? 1 : -1
        turnTo(dir, then: .greet, for: randRange(1.8, 2.4))
        remember(.played, 0.2)
        happy.velocity = 6
        setEmote(chance(0.6) ? .hearts : .sparkle, 1.1)
        decisionIn = max(decisionIn, 3)
    }

    /// Dancing along with a friend.
    func danceWithFriend() {
        guard canPlay else { return }
        wake()
        queued = nil
        beginActivity(chance(0.6) ? .dance : .drum, dur: randRange(1.6, 2.6))
        setEmote(.note, 1.4)
        remember(.played, 0.3)
        decisionIn = max(decisionIn, 2.5)
    }

    /// Goes over to see a friend.
    func visitFriend(at p: V2) {
        guard canPlay else { return }
        summon(to: p)
        decisionIn = max(decisionIn, 2)
    }

    /// A friend landed on it, or tagged it: a jump, and a look round.
    func startledByFriend() {
        guard mode == .attached, !isHeld else { return }
        wake()
        queued = nil
        beginActivity(.startle, dur: 0.55)
        startled.velocity = 10
        setEmote(.surprise, 0.7)
        queue(chance(0.5) ? .bounce : .wiggle, 0.9)
    }

    /// Caught one: a little victory.
    func taggedFriend() {
        guard mode == .attached else { return }
        queued = nil
        beginActivity(chance(0.5) ? .armsUp : .wiggle, dur: 0.9)
        happy.velocity = 7
        setEmote(.sparkle, 0.9)
        remember(.played, 0.3)
    }

    // MARK: Going home

    /// A visitor on its way out: which way it is heading off the screen,
    /// -1 left or +1 right. It walks to that side of the screen along
    /// whatever it is on — hopping across from one thing to the next if it
    /// has to — and at the edge leaps out past it, and is gone.
    private(set) var departing: CGFloat?
    /// Ran out of ledge on the way: leap on from here.
    private var departCornered = false
    /// The leap about to be made is the one out past the edge: nothing
    /// is caught hold of on the way.
    private var departLeap = false
    /// In the air on that leap: the rim of the screen does not stop it.
    private var flyingHome = false

    func depart() {
        guard departing == nil else { return }
        let f = map.screenFrame(containing: pos)
        // The nearer side — unless another display carries on past it and
        // the far side is the way out.
        let y = pos.y
        func openSide(_ d: CGFloat) -> Bool {
            !NSScreen.screens.contains { s in
                s.frame.minY < y && s.frame.maxY > y && (d > 0 ? abs(s.frame.minX - f.maxX) < 2 : abs(s.frame.maxX - f.minX) < 2)
            }
        }
        let nearer: CGFloat = pos.x - f.minX < f.maxX - pos.x ? -1 : 1
        departing = !openSide(nearer) && openSide(-nearer) ? -nearer : nearer
        friendChase = nil
        friendFlee = nil
        homing = nil
        huntTarget = nil
        endToyPlay(bored: false)
        cursorHunt = .none
        wake()
        queued = nil
        walkThen = nil
        if mode == .attached { decisionIn = min(decisionIn, 0.1) }
    }

    private func pursueDeparture(_ dir: CGFloat) {
        decisionIn = randRange(0.25, 0.5)
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        let sc = config.scale
        let f = map.screenFrame(containing: pos)
        let edgeX = dir > 0 ? f.maxX : f.minX
        let cornered = departCornered
        departCornered = false
        // At the edge: out past it, and away.
        let exit = V2(edgeX + dir * 220 * sc, min(pos.y + 80 * sc, f.maxY - 30))
        if abs(edgeX - pos.x) < 140 * sc, ballistic(from: pos, to: exit) != nil {
            departLeap = true
            startJump(to: exit)
            return
        }
        // Along this edge, if it runs that way.
        let seg = loop.segs[anchor.segIdx]
        if !cornered, abs(seg.dir.x) > 0.5 {
            let along: CGFloat = seg.dir.x * dir > 0 ? 1 : -1
            turnTo(along, then: .walk, for: clamp(abs(edgeX - pos.x) / max(config.walkSpeed, 1), 0.6, 3.0))
            return
        }
        // Otherwise across to whatever gets it furthest that way.
        var best: (gain: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) where spot.loop.id != anchor.loopID {
            let gain = (spot.point.x - pos.x) * dir
            guard gain > 30, spot.point.distance(to: pos) < 600,
                  let launch = ballistic(from: pos, to: spot.point), launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
            if best == nil || gain > best!.gain { best = (gain, spot.point) }
        }
        if let b = best {
            startJump(to: b.point)
        } else if ballistic(from: pos, to: exit) != nil {
            departLeap = true
            startJump(to: exit)
        } else {
            detachAndFall()
        }
    }


    // MARK: The pointer as prey

    /// Something it would not spare the pointer more than a glance for: a
    /// hunt, a chase, a job, a film, sleep, or a move already under way.
    private var preoccupied: Bool {
        guard mode == .attached, !inCinema, laser == nil, departing == nil, huntTarget == nil, caught == nil,
              homing == nil, build == nil, peek == nil, toyPlay == nil, t > escapeUntil, t >= bedBoundUntil,
              !(confined && !inBox), !hangOnly else { return true }
        if [.sleep, .eat, .watch, .peekaboo, .roll, .spin, .crouch, .shoot, .fasten, .scurry,
            .startle, .stretch, .shake, .bounce, .dance, .drum, .groove].contains(activity) { return true }
        return speed > config.walkSpeed * 1.5
    }

    /// What it would drop for a hunt: sitting about, an aimless walk, or
    /// its usual fuss over the pointer.
    private var distractable: Bool {
        !preoccupied && [.idle, .look, .rest, .stare, .glance, .fidget, .peer, .walk, .sneak,
                         .curious, .greet, .armsUp, .wave, .groom, .scratch].contains(activity)
    }

    /// How the pointer holds its attention, every frame. Interest builds
    /// while it hangs about close by and it has nothing better to do, and
    /// shows in the eyes, a tip of the head and a lean toward it; a pointer
    /// that fidgets close by for long enough gets stalked.
    private func updateInterest(dt: CGFloat) {
        let sc = config.scale
        let d = cursor.distance(to: pos)
        // A hunt only lives in the modes it belongs to: picked up, teleported
        // or knocked off mid-way, it is over.
        switch cursorHunt {
        case .none: break
        case .stalking: if mode != .attached { endCursorHunt(nextIn: 10) }
        case .pouncing:
            if mode == .attached ? !(activity == .crouch || activity == .turn) : mode != .airborne { endCursorHunt(nextIn: 10) }
        case .clinging: if mode != .clinging { endCursorHunt(nextIn: 20) }
        }
        if dt > 0 { cursorAcc = approach(cursorAcc, (cursorVel - prevCursorVel) / dt, 20, dt) }
        prevCursorVel = cursorVel

        // Fidgeting: every quick reversal of the pointer's direction near it
        // counts, and the score fades fast, so only a proper back-and-forth
        // wiggle — several reversals in a couple of seconds — adds up.
        if d < Spider.huntRange * sc {
            let sx: CGFloat = cursorVel.x > 150 ? 1 : (cursorVel.x < -150 ? -1 : 0)
            let sy: CGFloat = cursorVel.y > 150 ? 1 : (cursorVel.y < -150 ? -1 : 0)
            if sx != 0, sx != wiggleSign.x { if wiggleSign.x != 0 { cursorWiggle += 0.3 }; wiggleSign.x = sx }
            if sy != 0, sy != wiggleSign.y { if wiggleSign.y != 0 { cursorWiggle += 0.3 }; wiggleSign.y = sy }
        } else {
            wiggleSign = .zero
        }
        cursorWiggle = max(0, min(cursorWiggle, 3) - dt * 0.7)
        if d < Spider.interestRange * sc {
            cursorNearFor += dt
        } else {
            cursorNearFor = max(0, cursorNearFor - dt * 3)
            if cursorNearFor == 0 { boredAfter = randRange(10, 22) }
        }
        // A pointer that just sits there is old news after a while: it
        // loses interest and goes about its business, until the pointer
        // goes away and comes back — or livens up.
        let bored = cursorNearFor > boredAfter && cursorWiggle < 0.5

        // Interest: quick to take, slow to fade — unless it has something
        // else to do, in which case it barely spares the pointer a glance.
        // Something going off on the screen takes it over from the pointer
        // for a moment, however far off it is.
        let busy = preoccupied
        // (Something in the tank it has its eyes on holds them as the
        // pointer would.)
        let eyes = t < eyeOnUntil && mode == .attached ? eyeOn : nil
        let focus = noticing ? commotionAt : (eyes ?? cursor)
        let wants = noticing || eyes != nil || config.followCursor && !busy && !bored && d < Spider.interestRange * sc && cursorFree(cursor)
            && t - lastUserActivity < 8 && cursorHunt == .none
        interest = approach(interest, wants ? 1 : 0, wants ? 6.0 : (busy ? 4 : 1.2), dt)
        // Where the pointer is, give or take its fidgeting: what a pounce
        // is aimed at.
        cursorCentre = approach(cursorCentre, cursor, 7, dt)
        var nose: CGFloat = 0
        if interest > 0.01, mode == .attached {
            // The pointer's bearing in the ledge's frame — +x the way the
            // ledge runs, +y away from the surface — as a direction that
            // shrinks toward nothing with the pointer right on top of it,
            // where its bearing swings about wildly: there it just looks up
            // at you.
            let a = (focus - pos).rotated(by: -heading)
            let r = max(a.length, 30 * sc)
            var c = a.x / r
            let s = a.y / r
            // It points itself at the pointer, all of it at once and all of
            // it continuously: the face turns to it (yaw the cosine of its
            // bearing, so ahead is side on, straight above is face on and
            // behind is the other side), the head tips up or down to it and
            // the abdomen tips the other way, so head and tail line up on
            // it. Turned toward it like that, the nose comes up by
            // atan(0.9 s) to point right at it — side on, face on or
            // anywhere between.
            nose = clamp(atan(0.9 * s), -0.6, 0.75)
            headYawTarget = 0.9 * c
            // The legs come round after the head and abdomen, on a smoothed
            // bearing — and only once those have gone well round from them,
            // so for the pointer's smaller movements the feet stay planted
            // and the upper body does the following. Ahead they stop just
            // short of full profile so a little face still shows; on the
            // move they only come three-quarters round, so it never walks
            // backwards. They go right round to the other side, through the
            // front view, once the pointer is clearly round there — not the
            // moment it passes overhead, so it does not flicker between
            // mirror images with the pointer hovering right above it — and
            // not in the middle of a gesture, which finishes on the side it
            // began.
            if speed > 1 || [.walk, .scurry, .sneak].contains(activity) {
                c = facing * max(facing * c, 0.45)
                // Nor do the head and abdomen turn back past the front view
                // the way it came: it would be walking backwards with its
                // eyes on you. It looks round at you as it goes; for a
                // proper look behind it stops (and the walk is dropped for
                // it, below).
                headYawTarget = facing * max(facing * headYawTarget, 0.3)
            }
            interestBearing = approach(interestBearing, c, 2.4, dt)
            // (A stare follows it round too: only a gesture with its legs
            // up finishes on the side it began.)
            let gesturing = Spider.gestures.contains(activity)
            // The head turned as far round from the legs as it goes (or, in
            // something lopsided, as far as the front view), with the
            // pointer gone on round the other side: the legs come round at
            // once, so it never sits stuck looking at you while the pointer
            // goes on by.
            let pinned = headPinnedFor > 0.12
            let lead = pinned ? c : interestBearing
            if lead * interestSide < -(pinned ? 0.05 : Spider.sideSwitch), !gesturing {
                sideSwitchFor += dt
                if sideSwitchFor > (pinned ? 0.08 : Spider.sideSwitchAfter) { interestSide = -interestSide; sideSwitchFor = 0 }
            } else if lead * interestSide < -Spider.sideSwitch, interest > 0.75,
                      [.curious, .greet, .armsUp, .wave].contains(activity), activityTime > 0.4 {
                // Its fuss over the pointer, with the pointer gone on round
                // the other side: dropped, to turn and keep its eyes on it.
                sideSwitchFor += dt
                if sideSwitchFor > Spider.sideSwitchAfter {
                    queued = nil
                    beginActivity(.look, dur: randRange(1.0, 2.0))
                }
            } else {
                sideSwitchFor = max(0, sideSwitchFor - dt * 2)
            }
            // (And once the pointer has been still a while, they finish
            // coming round to it — a last small shuffle of the feet.)
            let stance = interestSide * max(interestSide * interestBearing, 0.12) * 0.88
            let off = abs(stance - interestYawTarget)
            stanceOffFor = off > Spider.stanceShift * 0.4 ? stanceOffFor + dt : 0
            if (stance >= 0) != (interestYawTarget >= 0) || off > Spider.stanceShift || stanceOffFor > Spider.stanceSettle {
                interestYawTarget = stance
                stanceOffFor = 0
            }
        }
        if interest < 0.05 {
            // Not following anything: start from however it stands.
            interestSide = facing
            interestBearing = yaw
            interestYawTarget = yaw
            headYawTarget = yaw
            sideSwitchFor = 0
        }
        interestNose.step(to: nose * interest, dt: dt)

        // An aimless walk is dropped for a better look — soon, with the
        // pointer round behind it, where its head can't follow as it goes.
        let behind = interest > 0.75 && headYawTarget * facing < -0.2
        if interest > 0.75, activity == .walk, activityTime > 0.5, walkPauseAt > 90 || activityTime < walkPauseAt,
           walkGoal == nil, eyes == nil, chance(dt * (behind ? 4 : 1.2)) {
            queued = nil
            walkThen = nil
            beginActivity(.look, dur: randRange(1.0, 2.4))
        }

        // Fidgeting close by like something alive — and it has been a while
        // since the last hunt: it is stalked. A pointer that merely sits
        // there is only watched.
        let fidgeting = cursorWiggle > 1.8 && cursorNearFor > 0.6
        guard config.pounceOnCursor, config.followCursor, cursorHunt == .none, !noticing, distractable, t > nextCursorHuntAt,
              interest > 0.5, fidgeting, d < Spider.huntRange * sc,
              cursorFree(cursor), chance(dt * 2.5) else { return }
        beginCursorHunt()
    }

    /// Locks on: a freeze, then the stalk begins.
    private func beginCursorHunt() {
        cursorHunt = .stalking
        cursorHuntSince = t
        cursorPoised = false
        cursorStalls = 0
        cursorStalkLastPos = pos
        cursorWiggle = 0
        queued = nil
        walkThen = nil
        glance = 0
        beginActivity(.look, dur: randRange(0.5, 0.9))
        decisionIn = 0.05
    }

    /// The hunt is over, one way or another; the next may come after `nextIn`.
    private func endCursorHunt(nextIn: CGFloat) {
        cursorHunt = .none
        cursorPoised = false
        huntPounce = false
        pounceMark = nil
        nextCursorHuntAt = t + nextIn / lerp(0.6, 1.5, personality.playfulness)
        cursorWiggle = 0
        cursorNearFor = 0
    }

    /// The stalk, one decision at a time: creeps along its ledge to within a
    /// spring of the pointer, gathers itself — poised, wiggling — and pounces.
    private func stalkCursor() {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else {
            endCursorHunt(nextIn: 10)
            return
        }
        let sc = config.scale
        let d = cursor - pos
        let dist = d.length
        // Gone off, or it has been at this too long: it gives up, puzzled.
        if dist > 460 * sc || t - cursorHuntSince > 14 || !cursorFree(cursor) || inCinema
            || t - lastUserActivity > 6 {
            endCursorHunt(nextIn: randRange(10, 20))
            beginActivity(.look, dur: randRange(0.8, 1.5))
            setEmote(.question, 1.1)
            return
        }
        decisionIn = randRange(0.2, 0.5)
        // Going nowhere (blocked, say): after a few tries it springs from here.
        if pos.distance(to: cursorStalkLastPos) < 10 * sc { cursorStalls += 1 } else { cursorStalls = 0 }
        cursorStalkLastPos = pos
        let seg = loop.segs[anchor.segIdx]
        let along = d.dot(seg.dir)
        let dir: CGFloat = along >= 0 ? 1 : -1
        let facingIt = along * walkDir >= 0 || abs(along) < 10 * sc
        let inReach = abs(along) < 100 * sc && dist < 260 * sc && ballistic(from: pos, to: cursor) != nil

        if inReach || cursorStalls >= 4 {
            if !facingIt, cursorStalls < 4 {
                // Close, but it is behind: round to face it, and no further.
                turnTo(dir, then: .look, for: 0.15)
                return
            }
            // Poised: the crouch with the pounce wiggle, and a beat to let
            // the pointer settle — a while longer if it is dashing about,
            // but not for ever.
            let dashing = cursorVel.length > 300
            if cursorStalls < 4, !cursorPoised || (dashing && t - cursorPoisedAt < 2.5) {
                if !cursorPoised { cursorPoisedAt = t }
                cursorPoised = true
                pendingJump = nil
                beginActivity(.crouch, dur: randRange(0.4, 0.7))
                return
            }
            pounceAtCursor()
            return
        }
        // Closing in: a sneak for the last stretch, a walk before that.
        let style: Activity = abs(along) < 220 * sc ? .sneak : .walk
        let speed = style == .sneak ? config.walkSpeed * 0.42 : config.walkSpeed
        let want = max(abs(along) - 70 * sc, 20 * sc)
        turnTo(dir, then: style, for: clamp(want / max(speed, 1) * 0.85, 0.35, 2.5))
    }

    /// Where a pounce goes: where the pointer is, give or take its fidgeting,
    /// a touch ahead of its drift, and a touch beyond for the air it flies
    /// through. Straight through the face of whatever it stands on if the
    /// pointer is over that: it is drawn in front of everything, so a leap
    /// onto the glass reads.
    private func aimPounceAtCursor() {
        var mark = cursorCentre + cursorVel.clampedLength(300) * 0.06
        mark += (mark - pos) * 0.05
        pounceMark = mark
        pendingJump = mark
        glassLeap = (mark - pos).dot(surfaceNormal) < 0
    }

    private func pounceAtCursor() {
        lastPounceAt = t
        cursorHunt = .pouncing
        huntPounce = true
        aimPounceAtCursor()
        beginActivity(.crouch, dur: randRange(0.28, 0.42))
    }

    /// Got it! It hangs off the pointer by its front legs.
    private func catchCursor() {
        remember(.played)
        remember(.huntWon, 0.5)
        cursorHunt = .clinging
        mode = .clinging
        huntPounce = false
        pounceMark = nil
        pendingJump = nil
        landing = nil
        landingReach = 0
        draglineCatchY = nil
        airShot = nil
        detachWeb(fade: true)
        clingOffset0 = pos - cursor
        clingBlend = 0
        clingSwing = 0
        clingSwingVel = clamp(vel.x * 0.004, -3, 3)
        clingShake = 0
        clingShakeSign = .zero
        clingSince = t
        clingFor = randRange(3.5, 7.0) * lerp(0.8, 1.3, personality.playfulness)
        vel = .zero
        speed = 0
        legMode = .free
        happy.velocity = 7
        stretch.velocity = 4
        setEmote(.sparkle, 0.9)
        queued = nil
        activity = .idle
        activityTime = 0
    }

    /// Hanging off the pointer: mouth on the hotspot, body swinging below
    /// it as a pendulum driven by the pointer's jerks. It holds on for a
    /// while and drops away on a line; shaken hard back and forth, it is
    /// flung off.
    private func updateClinging(dt: CGFloat) {
        let sc = config.scale
        // The pointer has gone somewhere it cannot follow.
        if !map.isOnScreen(cursor, slack: 20) || cursor.distance(to: pos) > 400 * sc || !cursorFree(cursor) {
            letGoOfCursor(flung: false)
            return
        }
        // Shaking: each reversal of a quick back-and-forth loosens its grip.
        let sx: CGFloat = cursorVel.x > 260 ? 1 : (cursorVel.x < -260 ? -1 : 0)
        let sy: CGFloat = cursorVel.y > 260 ? 1 : (cursorVel.y < -260 ? -1 : 0)
        if sx != 0, sx != clingShakeSign.x { if clingShakeSign.x != 0 { clingShake += 0.55; startled.velocity = 4 }; clingShakeSign.x = sx }
        if sy != 0, sy != clingShakeSign.y { if clingShakeSign.y != 0 { clingShake += 0.55; startled.velocity = 4 }; clingShakeSign.y = sy }
        clingShake = max(0, clingShake - dt * 0.9)
        if clingShake > 1.6 {
            letGoOfCursor(flung: true)
            return
        }
        if t - clingSince > clingFor {
            letGoOfCursor(flung: false)
            return
        }

        // The pendulum: hung from the hotspot, swung by the pointer's
        // sideways jerks, and given a shake of its own when it struggles.
        let len = 30 * sc
        let drive = clamp(cursorAcc.x, -9000, 9000)
        var acc = -(1950 / len) * sin(clingSwing) * 0.55 - clingSwingVel * 2.8 - (drive / len) * cos(clingSwing) * 0.35
        if clingShake > 0.5 { acc += sin(t * 23) * 40 * clingShake }
        clingSwingVel += acc * dt
        clingSwing += clingSwingVel * dt
        clingSwing = clamp(clingSwing, -1.4, 1.4)
        headingTarget = facing * .pi / 2 + clingSwing

        // Mouth on the hotspot, from wherever it took hold.
        clingBlend = approach(clingBlend, 1, 6, dt)
        let hd = SpiderRenderer.head(for: look)
        let mouth = V2((hd.c.x + hd.r * 0.55) * mirrorSign, hd.c.y - hd.r * 0.62).rotated(by: heading) * sc
        let prev = pos
        pos = cursor + V2.lerp(clingOffset0, -mouth, smoothstep(clingBlend))
        if dt > 0 { vel = (pos - prev) / dt }

        legMode = .free
        stretch.step(to: 1.04 + clamp(clingShake, 0, 1.6) * 0.04, dt: dt)
        crouch.step(to: 0, dt: dt)
        lift.step(to: 0, dt: dt)
        pitch.step(to: 0, dt: dt)
        wag.step(to: clingShake > 0.5 ? 0.6 : 0.15, dt: dt)
        lid.step(to: 0, dt: dt)
        happy.value = max(happy.value, clingShake > 0.8 ? 0 : 0.5)
    }

    /// Off the pointer: flung, it flies with the pointer's motion and
    /// catches itself on a line; otherwise it lets go and drops away on
    /// one, pleased with itself.
    private func letGoOfCursor(flung: Bool) {
        endCursorHunt(nextIn: flung ? randRange(14, 26) : randRange(20, 45))
        mode = .airborne
        air = flung ? .thrown : .fall
        airTime = 0
        noAttachFor = 0.08
        launchLoop = ""
        legMode = .free
        if flung {
            remember(.thrown, 0.6)
            vel = (cursorVel.clampedLength(1500) * 0.7 + V2(0, 120)).clampedLength(1600)
            startled.velocity = 10
            setEmote(.surprise, 0.7)
        } else {
            vel = cursorVel.clampedLength(300) * 0.3 + V2(0, -40)
            happy.velocity = 8
            setEmote(.hearts, 1.3)
        }
        if vel.length < Spider.hardThrow { planFall(from: nil, lineUp: true) }
        stretch.velocity = -4
    }

    // MARK: Beds

    /// Standing on the top edge of a window.
    private var onWindowTop: Bool {
        guard mode == .attached, let loop = map.loop(anchor.loopID), loop.kind == .windowEdge,
              anchor.segIdx < loop.segs.count else { return false }
        return loop.segs[anchor.segIdx].facing == .up
    }

    /// A bed it can get to: the top of the window it is already on (round
    /// the corner), or the top of a window it can leap onto from here.
    private func nearestWindowTop() -> (point: V2, anchor: Anchor, sameLoop: Bool)? {
        guard mode == .attached else { return nil }
        var best: (d: CGFloat, p: V2, a: Anchor, same: Bool)?
        for spot in map.sampleSpots(spacing: 40) where spot.loop.kind == .windowEdge && spot.seg.facing == .up {
            guard spot.seg.isOpen(at: spot.anchor.t) else { continue }
            let d = spot.point.distance(to: pos)
            if spot.loop.id == anchor.loopID {
                guard d > 30 else { continue }
                if best == nil || d * 0.5 < best!.d { best = (d * 0.5, spot.point, spot.anchor, true) }
            } else {
                guard d > 60, let launch = ballistic(from: pos, to: spot.point),
                      launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
                if best == nil || d < best!.d { best = (d, spot.point, spot.anchor, false) }
            }
        }
        return best.map { ($0.p, $0.a, $0.same) }
    }

    /// One step toward the bed: round its own window to the top, or a leap
    /// onto the top of another.
    private func goToBed() {
        guard mode == .attached, let bed = nearestWindowTop(), let loop = map.loop(anchor.loopID) else { bedBoundUntil = -1; return }
        decisionIn = randRange(0.4, 1.0)
        if bed.sameLoop {
            var way: (d: CGFloat, dir: CGFloat)?
            for dir in [CGFloat(1), -1] {
                if let d = loopDistance(loop, to: bed.anchor, dir: dir), way == nil || d < way!.d { way = (d, dir) }
            }
            if let w = way {
                turnTo(w.dir, then: .walk, for: clamp(w.d / max(config.walkSpeed, 1), 0.8, 4.0))
            } else {
                bedBoundUntil = -1
            }
            return
        }
        startJump(to: bed.point)
    }

    // MARK: Thoughts

    /// Puts a thought in a bubble over its head for a while.
    func think(_ th: Thought, for dur: CGFloat = 3.2) {
        // No bubbles over a film.
        guard !inCinema else { return }
        thought = th
        setEmote(.thought, dur)
        lastThought = t
    }

    /// Something to think about, in words: one of its phrases, if it has any.
    func thinkSomething() {
        let lines = design.allPhrases
        guard let line = lines.randomElement() else { return }
        // Longer lines get longer to read.
        think(.text(line), for: clamp(2.2 + CGFloat(line.count) * 0.06, 2.8, 7))
    }

    /// A thought that fits the moment, or a random one.
    private func museIfSoMoved() {
        guard mode == .attached, emote == .none, t - lastThought > (raining ? 9 : 14) else { return }
        let P = personality
        let roll = CGFloat.random(in: 0...1)
        if fed < 0.15, prey.isEmpty, roll < 0.35 {
            think(.hungry)
        } else if raining, chance(0.5) {
            think(.rain)
        } else if let th = weatherThought(), chance(0.55) {
            think(th)
        } else if roll < 0.55 {
            thinkSomething()
        } else if roll < 0.7, t - lastUserActivity < 20 {
            think(P.affection > 0.5 ? .heart : .star)
        } else if roll < 0.8 {
            think([.rain, .sun, .moon, .music, .bug, .home].randomElement()!)
        }
    }

    // MARK: Weather
    //
    // In the habitat it is out in the weather (see Weather.swift). Rain
    // soaks it — a darker, glossy coat beaded with water, drips falling off
    // it — until it shakes itself off; snow settles on its back while it
    // keeps still, and slides off when it moves; sand gets in its fur. The
    // wind pushes it about on its feet and blows it out sideways on its
    // line, its legs streaming; it leans into it, and holds on through the
    // big gusts. When it comes down hard it runs for cover — under a
    // branch, the leaves of a plant — and sits it out there; thunder makes
    // it jump; it basks in the sun and stops to look up at a rainbow. Out
    // of the weather (on the desktop), it dries off and all of this stops:
    // with none of it on it, nothing here does anything at all.

    /// Any weather on it, or chill left in it.
    private var weatherOnIt: Bool { !weather.isCalm || chill > 0 }

    /// How hard the wind pushes, in points a second squared (+: to the
    /// right). A gale holds it out on its line at about 15°, a big gust
    /// at 25°.
    private var windPush: CGFloat { weather.wind * 520 }

    private func updateWeather(dt: CGFloat) {
        let w = weather
        guard weatherOnIt || wet > 0 || snowOn > 0 || dust > 0 || !drops.isEmpty else { return }
        if w.isCalm {
            windOn.reset(0)
            sheltered = false
        } else {
            windOn.step(to: w.wind, dt: dt)
            // Under something, or out in it (looked at now and then).
            shelterCheckIn -= dt
            if shelterCheckIn <= 0 {
                shelterCheckIn = 0.3
                sheltered = isSheltered()
            }
        }
        let out = !sheltered && !isHeld
        // Soaked by the rain (dewy in fog); drying off in time — quicker in
        // the sun, the heat and the wind.
        let soak = out ? w.rain : 0
        if soak > 0.02 {
            wet = min(1, wet + soak * dt / 11)
        } else if wet < w.fog * 0.35 {
            wet = min(w.fog * 0.35, wet + dt / 45)
        } else if wet > 0 {
            // (Barely at all under cover with it pouring all round.)
            let dry = (1 / 110 + w.sun / 25 + w.heat / 20 + abs(w.wind) / 60) * (w.rain > 0.05 ? 0.2 : 1)
            wet = max(0, wet - dry * dt)
        }
        // Snow settles on it standing out in it — thickest keeping still —
        // and melts away after, into its coat; tipped over (a wall, upside
        // down, a leap, a dash) it slides off.
        let onTop = mode == .attached && surfaceNormal.y > 0.6
        if out, w.snow > 0.02, onTop {
            snowOn = min(1, snowOn + w.snow * (speed < 6 ? 1 : 0.35) * dt / 24)
        }
        if snowOn > 0 {
            let tipped = !onTop || speed > 45
            var off: CGFloat = w.snow > 0.02 ? 0 : dt * (1 / 70 + w.heat / 8 + w.sun / 12 + w.rain / 10)
            if tipped {
                off += dt * 1.1
                if chance(dt * 12 * snowOn) { flingOff(.snow, count: 1) }
            } else {
                wet = min(1, wet + min(off, snowOn) * 0.5)
            }
            snowOn = max(0, snowOn - off)
            if off > 0, snowOn < 0.002 { snowOn = 0 }
        }
        // Sand in its fur.
        if out, w.sand > 0.02 {
            dust = min(1, dust + w.sand * dt / 16)
        } else if dust > 0 {
            dust = max(0, dust - dt / 160)
        }
        // Chilled by the cold, and by being wet in a wind.
        let cold = w.isCalm ? 0 : min(1, w.cold + wet * abs(w.wind) * 0.2 + snowOn * 0.25) * (sheltered ? 0.75 : 1) * (activity == .bask ? 0.5 : 1)
        chill = approach(chill, cold, 0.3, dt)
        if cold == 0, chill < 0.003 { chill = 0 }

        // Drips off it; rain splashing on its back; hail glancing off it.
        if wet > 0.12 {
            dripIn -= dt * (0.5 + wet * 2.5)
            if dripIn <= 0 { dripIn = randRange(0.7, 1.3); drip() }
        }
        if out, w.rain > 0.15 {
            splashIn -= dt * w.rain * 6
            if splashIn <= 0 { splashIn = randRange(0.6, 1.4); rainSplash() }
        }
        if out, w.hail > 0.05 {
            hailIn -= dt * w.hail
            if hailIn <= 0 { hailIn = randRange(1.4, 3.6); hailHit() }
        }
        stepDrops(dt: dt)
    }

    /// Something new in the weather: it takes notice.
    private func weatherArrived(_ old: WeatherFeel) {
        let w = weather
        guard mode == .attached, activity != .sleep, emote == .none, !inCinema, t - lastThought > 5 else { return }
        if old.rain < 0.15, w.rain >= 0.15 {
            think(.rain, for: 2.8)
            skyLook(1.6)
        } else if old.snow < 0.15, w.snow >= 0.15 {
            think(.snow, for: 2.8)
            skyLook(2.2)
        } else if old.storm < 0.3, w.storm >= 0.3 {
            think(.storm, for: 2.8)
        } else if abs(old.wind) < 0.8, abs(w.wind) >= 0.8, t - lastThought > 45 {
            think(.wind, for: 2.4)
        } else if old.rainbow < 0.4 && w.rainbow >= 0.4 || old.skyShow < 0.4 && w.skyShow >= 0.4 {
            // (It looks up at it next time it thinks: see `weatherMind`.)
            decisionIn = min(decisionIn, 0.6)
        }
    }

    /// What the weather has it do, if anything: shaking off, running for
    /// cover and sitting a downpour out, splashing about in a warm rain,
    /// bracing, basking, looking up at the sky. True if it did something.
    private func weatherMind() -> Bool {
        guard mode == .attached else { return false }
        let w = weather
        let P = personality
        // On its way under cover: onward.
        if coverGoal != nil, pursueCover() { return true }
        // Shaking itself off: once the worst is over, or now and then when
        // it is soaked; straight away with snow piled on it.
        if t - lastShakeOff > 6, (wet > 0.4 && (!w.rough || sheltered || chance(0.15))) || snowOn > 0.45 || dust > 0.4 {
            beginActivity(.shake, dur: 0.7)
            queue(.groom, randRange(1.2, 2.0))
            return true
        }
        guard !w.isCalm else { return false }
        // In its tank: the weather getting to it out here, a hot sun, a gale
        // shaking what it is on (see "The tank alive").
        if eco != nil, ecoWeather() { return true }
        if w.rough, !sheltered {
            // Coming down hard: into cover, if there is any within reach —
            // the timid at once, the bold once it gets heavy.
            let urge = lerp(0.95, 0.35, P.bravery) * (w.hail > 0.1 || w.storm > 0.3 ? 1.5 : 1) * (wet > 0.5 ? 1.2 : 1)
            if chance(min(urge, 1)), placesOn ? seekShelter() : seekCover() { return true }
            // Nowhere to go, or it does not mind: a playful one splashes
            // about in a warm rain; otherwise it hunkers down and holds on.
            if w.rain > 0.25, w.storm < 0.2, w.hail < 0.05, w.cold < 0.5, chance(lerp(0, 0.45, P.playfulness)) {
                beginActivity(.dance, dur: randRange(1.2, 2.0))
                setEmote(.note, 1.2)
                return true
            }
            if chance(0.5) {
                beginActivity(.brace, dur: randRange(2, 4))
                return true
            }
            return false
        }
        // Only up under the lid of its tank, at a pinch: better cover it
        // knows of, it goes to.
        if w.rough, sheltered, placesOn, mode == .attached, surfaceNormal.y < -0.5, map.owner(of: anchor) == 0,
           map.loop(anchor.loopID)?.kind == .screenBorder, chance(0.5), seekShelter() {
            return true
        }
        // In under something that grew there, with the house it was given
        // not far: over to that instead, now and then.
        if w.rough, sheltered, placesOn, errand == nil, chance(0.5), moveToBuiltShelter() { return true }
        if w.rough, sheltered {
            // Under cover: it sits it out — resting, watching it come down,
            // grooming the wet off.
            let roll = CGFloat.random(in: 0...1)
            if roll < 0.5 {
                beginActivity(.rest, dur: randRange(5, 12))
            } else if roll < 0.75 {
                skyLook(randRange(1.5, 2.8))
                beginActivity(.look, dur: randRange(1.5, 2.8))
            } else {
                beginActivity(.groom, dur: randRange(1.4, 2.4))
            }
            decisionIn = max(decisionIn, activityDur)
            return true
        }
        // Too hot, out in a blazing sun: into the shade. (In its tank alive,
        // a while of basking first: see `ecoWeather`.)
        if w.heat > 0.65, !sheltered, eco == nil, chance(0.2 * lerp(1.4, 0.7, P.bravery)), placesOn ? seekShelter() : seekCover() { return true }
        // Sunshine: it basks in it.
        if w.sun > 0.45, !sheltered, surfaceNormal.y > 0.6, chance(0.3 * lerp(0.6, 1.5, P.laziness)) {
            beginActivity(.bask, dur: randRange(6, 14))
            happy.velocity = 3
            if emote == .none, chance(0.4) { think(.sun) }
            return true
        }
        // The sky putting on a show — a rainbow, shooting stars, the
        // northern lights — it stops to look up at.
        if max(w.rainbow, w.skyShow) > 0.5, t - lastSkyLook > 25, chance(0.55) {
            lastSkyLook = t
            skyLook(randRange(2.5, 4))
            beginActivity(.look, dur: randRange(2.4, 3.6))
            happy.velocity = 4
            if emote == .none {
                if w.rainbow > 0.5 { think(.rainbow) } else { setEmote(.sparkle, 1.4) }
            }
            return true
        }
        // Snow coming down: the playful ones reach up for the flakes.
        if w.snow > 0.3, !sheltered, t - lastSkyLook > 18, chance(0.3 * lerp(0.4, 1.6, P.playfulness)) {
            lastSkyLook = t
            skyLook(2)
            beginActivity(.armsUp, dur: randRange(1.0, 1.6))
            return true
        }
        // Cold: it huddles up and lies low.
        if chill > 0.5, chance(0.3) {
            beginActivity(.rest, dur: randRange(6, 14))
            return true
        }
        return false
    }

    /// Worth going for cover from: coming down hard, or a blazing sun.
    private var wantsCover: Bool { weather.rough || weather.heat > 0.65 }

    /// Off to the nearest cover, if there is any. True if it set off.
    private func seekCover() -> Bool {
        guard let spot = coverSpot() else { return false }
        coverGoal = spot
        coverSince = t
        return pursueCover()
    }

    /// On its way to cover: onward — walking round (hurrying, if it is bad)
    /// or leaping across. False once it is there, has given up, or the
    /// weather has let up.
    private func pursueCover() -> Bool {
        guard let goal = coverGoal else { return false }
        if sheltered || !wantsCover || t - coverSince > 30 || map.loop(goal.anchor.loopID) == nil {
            coverGoal = nil
            return false
        }
        if goal.anchor.loopID == anchor.loopID, let way = loopWay(to: goal.anchor) {
            guard way.dist > 6 * config.scale else { coverGoal = nil; return false }
            let hurry = weather.hail > 0.1 || weather.storm > 0.3 || weather.rain > 0.6 || weather.sand > 0.5
            walkThen = nil
            queued = nil
            turnTo(way.dir, then: hurry ? .scurry : .walk,
                   for: clamp(way.dist / max(config.walkSpeed * (hurry ? 1.6 : 0.9), 1), 0.4, 6))
            return true
        }
        // On something else: a leap to it.
        if ballistic(from: pos, to: goal.point) != nil {
            startJump(to: goal.point)
            return true
        }
        coverGoal = nil
        return false
    }

    /// Which way round its loop to go to reach `a`, and how far.
    private func loopWay(to a: Anchor) -> (dir: CGFloat, dist: CGFloat)? {
        guard let loop = map.loop(anchor.loopID), a.loopID == anchor.loopID,
              a.segIdx < loop.segs.count, anchor.segIdx < loop.segs.count else { return nil }
        func along(_ x: Anchor) -> CGFloat { loop.segs[0..<x.segIdx].reduce(0) { $0 + $1.len } + x.t }
        let d = along(a) - along(anchor)
        guard loop.closed else { return (d >= 0 ? 1 : -1, abs(d)) }
        let per = loop.perimeter
        let ahead = d >= 0 ? d : d + per
        return ahead <= per - ahead ? (1, ahead) : (-1, per - ahead)
    }

    /// The nearest place out of the weather it could get to: best the floor
    /// under a branch or the leaves of a plant, then the underside of
    /// something, at a pinch the lid of the tank.
    private func coverSpot() -> (anchor: Anchor, point: V2)? {
        var best: (anchor: Anchor, point: V2, score: CGFloat)?
        for s in map.sampleSpots(spacing: 24) {
            let under = s.seg.facing == .down
            guard under || (s.seg.facing == .up && roofOver(s.point)) else { continue }
            var score = s.point.distance(to: pos)
            if under { score += s.loop.kind == .screenBorder ? 260 : 120 }
            if s.anchor.loopID != anchor.loopID { score += 90 }
            if best == nil || score < best!.score { best = (s.anchor, s.point, score) }
        }
        guard let b = best, b.score < 1100 * config.scale else { return nil }
        return (b.anchor, b.point)
    }

    /// Hanging under something, it is out of the weather; otherwise, so it
    /// is with anything over it.
    private func isSheltered() -> Bool {
        if mode == .nesting { return true }
        if mode == .attached, surfaceNormal.y < -0.5 { return true }
        return roofOver(pos)
    }

    /// Whether the underside of anything is over `p`: a branch, the leaves
    /// of a plant, whatever is raised off the ground — near enough over it
    /// to keep the weather off (a branch high up in a tall tank doesn't).
    /// (The lid of the tank is over everything: only right under it counts.)
    private func roofOver(_ p: V2) -> Bool {
        for l in map.loops {
            let segs = l.edge.isEmpty ? l.segs : l.edge
            // In the tank, the floor's own surface runs up over whatever
            // solid stands on it — a stone, a bark cave, an overhang — so
            // only its top is the lid; the undersides of the rest are roofs
            // like any other.
            let lid = l.kind == .screenBorder ? (l.owners.isEmpty ? -CGFloat.greatestFiniteMagnitude : segs.reduce(-CGFloat.greatestFiniteMagnitude) { max($0, $1.a.y, $1.b.y) } - 2) : 0
            for s in segs where s.facing == .down {
                // (Anywhere along it: a curved roof is made of short pieces.)
                let lo = min(s.a.x, s.b.x), hi = max(s.a.x, s.b.x)
                guard p.x >= lo, p.x < hi else { continue }
                let y = abs(s.b.x - s.a.x) > 0.01 ? s.a.y + (s.b.y - s.a.y) * (p.x - s.a.x) / (s.b.x - s.a.x) : max(s.a.y, s.b.y)
                guard y > p.y + 4, y - p.y < 320 * config.scale else { continue }
                if l.kind == .screenBorder, min(s.a.y, s.b.y) >= lid, y - p.y > 60 * config.scale { continue }
                return true
            }
        }
        return false
    }

    private func skyLook(_ dur: CGFloat) { skyLookUntil = max(skyLookUntil, t + dur) }

    /// Thunder: a clap right overhead is a fright — it jumps, and stares at
    /// where the lightning came down; a far-off rumble only turns its head,
    /// unless it is a nervous one.
    func thunder(at p: V2, loud: CGFloat) {
        guard !weather.isCalm else { return }
        let fright = loud > 0.75 || chance(loud * lerp(0.8, 0.15, personality.bravery))
        // (Out in it in its tank, a clap makes it want to be in all the more.)
        if eco != nil, !sheltered { weatherWorry = min(1.5, weatherWorry + loud * lerp(0.7, 0.1, personality.bravery)) }
        noticeCommotion(at: p, fright: fright)
    }

    /// A thought that goes with the weather, if there is any.
    private func weatherThought() -> Thought? {
        let w = weather
        guard !w.isCalm else { return nil }
        if w.storm > 0.3 { return .storm }
        if w.snow > 0.2 { return .snow }
        if w.rain > 0.2 { return .rain }
        if w.rainbow > 0.4 { return .rainbow }
        if abs(w.wind) > 0.8 { return .wind }
        if w.sun > 0.5 { return .sun }
        if w.skyShow > 0.4 { return .star }
        return nil
    }

    private func weatherPosture(_ p: inout Posture) {
        let w = weather
        let blow = windOn.value
        let exposed = !sheltered
        // Slower into the wind (quicker with it), and in the cold.
        if p.speed > 0 {
            let travel = V2(walkDir, 0).rotated(by: heading)
            p.speed *= clamp(1 + 0.3 * blow * travel.x * (exposed ? 1 : 0.3), 0.5, 1.4) * lerp(1, 0.78, chill)
        }
        // Holding on low in the wind, hunched up in the cold.
        p.crouch = min(1, p.crouch + min(abs(blow) * 0.22, 0.35) * (exposed ? 1 : 0.4) + chill * 0.12)
        // Leaning into the wind, on top of things.
        if surfaceNormal.y > 0.5, exposed {
            let nose = V2(mirrorSign, 0).rotated(by: heading)
            p.pitch += 0.12 * clamp(nose.dot(V2(blow, 0)), -1.4, 1.4)
        }
        if activity != .sleep {
            let squint = (w.sand * 0.55 + abs(blow) * 0.1 + w.snow * 0.12 + w.heat * 0.18 + w.sun * 0.1) * (exposed ? 1 : 0.4)
            p.lid = max(p.lid, min(squint, 0.6))
        }
    }

    // Drips and splashes.

    /// The lowest point on the body toward `c` (radii `r`), in sprite units.
    private func underside(_ c: V2, _ rx: CGFloat, _ ry: CGFloat) -> V2 {
        let down = toLocalDir(V2(0, -1))
        return c + V2(down.x * rx, down.y * ry) * 0.92
    }

    /// Where a drop falling off it lands: the ledge under it, standing on
    /// top of something; nothing (it falls a way and is gone) otherwise.
    private var dropFloor: CGFloat? {
        mode == .attached && surfaceNormal.y > 0.6 ? anchorPos.y - map.standoff : nil
    }

    private func drip() {
        guard drops.count < 26 else { return }
        let ab = SpiderRenderer.abdomen(for: look), hd = SpiderRenderer.head(for: look)
        // Off the bottom of the abdomen mostly; off the head now and then.
        let roll = CGFloat.random(in: 0...1)
        var at = roll < 0.7 ? underside(ab.c, ab.rx, ab.ry) : underside(hd.c, hd.r, hd.r)
        at.x += randRange(-4, 4)
        var d = Drop(p: toWorld(at), v: .zero, r: randRange(1.3, 2.1), kind: .water, life: 1.6, floor: dropFloor)
        d.hold = randRange(0.35, 0.8)
        d.at = at
        drops.append(d)
    }

    private func rainSplash() {
        guard drops.count < 26 else { return }
        let up = toLocalDir(V2(0, 1))
        let ab = SpiderRenderer.abdomen(for: look)
        let top = toWorld(ab.c + V2(up.x * ab.rx, up.y * ab.ry) * 0.95 + V2(randRange(-6, 6), 0))
        let sc = config.scale
        for _ in 0..<2 {
            drops.append(Drop(p: top, v: V2(randRange(-60, 60), randRange(40, 90)) * sc, r: randRange(0.6, 1.0),
                              kind: .water, life: 0.35, floor: nil))
        }
    }

    private func hailHit() {
        let up = toLocalDir(V2(0, 1))
        let ab = SpiderRenderer.abdomen(for: look)
        let top = toWorld(ab.c + V2(up.x * ab.rx, up.y * ab.ry))
        let sc = config.scale
        if drops.count < 26 {
            drops.append(Drop(p: top, v: V2(randRange(-80, 80), randRange(70, 130)) * sc, r: 1.8, kind: .hail,
                              life: 1.1, floor: dropFloor, gravity: 1300))
        }
        // Ow.
        startled.velocity = max(startled.velocity, 5)
        guard mode == .attached else { return }
        crouch.velocity += 4
        if emote != .thought, chance(0.45) { setEmote(.exclaim, 0.55) }
        // Out from under it, soon.
        if !sheltered, coverGoal == nil, [.idle, .look, .rest, .bask, .groom, .glance, .stare, .fidget].contains(activity) {
            queued = nil
            walkThen = nil
            finishActivity()
            decisionIn = min(decisionIn, 0.2)
        }
    }

    /// Bits of whatever is on it thrown off: snow, water, dust.
    private func flingOff(_ kind: Speck.Kind, count: Int) {
        let ab = SpiderRenderer.abdomen(for: look)
        let sc = config.scale
        for _ in 0..<count where drops.count < 26 {
            let a = randRange(0, 2 * .pi)
            let at = V2(ab.c.x + cos(a) * ab.rx * 0.9, ab.c.y + sin(a) * ab.ry * 0.9)
            let dir = (toWorld(at) - toWorld(ab.c)).normalized
            let snow = kind == .snow
            drops.append(Drop(p: toWorld(at), v: dir * randRange(90, 200) * sc + V2(0, 50 * sc),
                              r: snow ? randRange(1.6, 2.6) : (kind == .sand ? randRange(0.7, 1.1) : randRange(0.9, 1.6)),
                              kind: kind, life: snow ? 0.8 : 0.6, floor: dropFloor, gravity: snow ? 500 : 900))
        }
    }

    /// A good shake: most of the water, all the snow and most of the dust
    /// go flying.
    private func shakeOff() {
        guard wet > 0.03 || snowOn > 0.03 || dust > 0.03 else { return }
        lastShakeOff = t
        flingOff(.water, count: Int(wet * 12))
        flingOff(.snow, count: Int(snowOn * 12))
        flingOff(.sand, count: Int(dust * 10))
        wet *= 0.45
        snowOn = 0
        dust *= 0.3
    }

    private func stepDrops(dt: CGFloat) {
        guard !drops.isEmpty else { return }
        let sc = config.scale
        for i in drops.indices.reversed() {
            var d = drops[i]
            d.age += dt
            if d.hold > 0 {
                // Swelling where it gathers, carried along with it.
                d.hold -= dt
                d.p = toWorld(d.at)
                if d.hold <= 0 { d.v = vel * 0.3 + V2(0, -30 * sc) }
            } else if d.sip {
                // (Drunk from: going down.)
                if activity == .drink { d.r = max(0.35, d.r - dt * 0.45) }
            } else if d.kind != .ring {
                d.v.y -= d.gravity * sc * dt
                // The light ones blow about.
                if d.kind != .hail { d.v.x += windPush * (d.kind == .water ? 0.25 : 0.6) * dt }
                d.p += d.v * dt
                if let f = d.floor, d.p.y <= f, d.v.y < 0 {
                    switch d.kind {
                    case .water:
                        d = Drop(p: V2(d.p.x, f), v: .zero, r: d.r * 1.8, kind: .ring, life: 0.3, floor: nil)
                    case .hail:
                        // A bounce or two.
                        d.p.y = f
                        d.v = V2(d.v.x * 0.6, -d.v.y * 0.35)
                        if d.v.y < 25 * sc { d.floor = nil; d.life = min(d.life, d.age + 0.25) }
                    default:
                        d.life = min(d.life, d.age + 0.12)
                        d.floor = nil
                    }
                }
            }
            if d.age > d.life || d.p.distance(to: pos) > 64 * sc {
                drops.remove(at: i)
            } else {
                drops[i] = d
            }
        }
    }

    /// The weather on it, for the renderer.
    private func weatherPose(_ p: inout SpiderPose) {
        p.wet = wet
        p.snow = snowOn
        p.dust = dust
        p.chill = chill
        let sc = config.scale
        p.specks = drops.map { d -> Speck in
            switch d.kind {
            case .ring:
                let u = clamp(d.age / d.life, 0, 1)
                return Speck(p: d.p - pos, r: d.r * sc * (1 + u * d.spread), kind: .ring, alpha: 1 - u)
            default:
                let grow = d.hold > 0 ? clamp(d.age / max(d.age + d.hold, 0.01), 0.35, 1) : 1
                let fade = clamp((d.life - d.age) / 0.25, 0, 1)
                let stretch = d.kind == .water && d.hold <= 0 ? 1 + min(abs(d.v.y) / (350 * sc), 1.4) : 1
                return Speck(p: d.p - pos, r: d.r * sc * grow, kind: d.kind, alpha: fade, stretch: stretch)
            }
        }
        // Shivering in the cold: small and quick, in bursts.
        if chill > 0.3, mode == .attached, activity != .sleep {
            let bursts = max(0, sin(t * 1.3) + 0.3)
            let s = (chill - 0.3) * 0.9 * bursts * sin(t * 53)
            p.bodyShift.x += s
            p.abdomenSway += s * 0.05
        }
        // The gusts ruffle it.
        if !weather.isCalm, !sheltered, abs(windOn.value) > 0.2 {
            p.abdomenSway += sin(t * 9.7) * min(abs(windOn.value), 1.5) * weather.gust * 0.05
        }
    }

    /// Tools only: weather on it now, and a word on how it is.
    func debugWeatherOn(wet w: CGFloat? = nil, snow s: CGFloat? = nil, dust d: CGFloat? = nil) {
        if let w { wet = w }
        if let s { snowOn = s }
        if let d { dust = d }
    }
    var debugWeather: String {
        String(format: "wet %.2f snow %.2f dust %.2f chill %.2f %@ drops %d%@", wet, snowOn, dust, chill,
               sheltered ? "sheltered" : "out", drops.count, coverGoal != nil ? " → cover" : "")
    }

    // MARK: Drumming

    /// 1 during a burst of drumming, 0 in the pauses between: bursts of
    /// about a second with short rests, over the activity.
    private func drumBeat() -> CGFloat {
        let cycle: CGFloat = 1.45
        let u = activityTime.truncatingRemainder(dividingBy: cycle) / cycle
        return u < 0.72 ? 1 : 0
    }

    /// Where a front foot is in its tap, 0..1: alternating in the quick
    /// bursts (about eight taps a second), together for the slower beats
    /// that finish each burst.
    private func drumPhase(near: Bool) -> CGFloat {
        let cycle: CGFloat = 1.45
        let u = activityTime.truncatingRemainder(dividingBy: cycle) / cycle
        if u < 0.5 {
            // Quick alternating taps.
            let taps = activityTime * 6 + (near ? 0 : 0.5)
            return taps.truncatingRemainder(dividingBy: 1)
        } else if u < 0.72 {
            // Three slower beats together.
            let beats = (u - 0.5) / 0.22 * 3
            return beats.truncatingRemainder(dividingBy: 1)
        }
        return 0
    }

    // MARK: Dancing to music

    /// Music playing on the Mac, with its beat: set every frame by whoever
    /// can hear it, nil while nothing with a beat is playing.
    var music: MusicBeat?

    /// The moves of a dance to music. Each is kept up for a phrase —
    /// eight pulses — and the next one comes in on the bar.
    private enum GrooveMove: String, CaseIterable {
        case bob        // bouncing on the beat, the front feet tapping it in turn
        case stomp      // marching on the spot, each set of feet coming down on the beat
        case pump       // the front legs pumping up in turn, one a beat
        case peacock    // abdomen raised and swinging, the hind legs fanned up behind like tail feathers
        case arms       // turned square on to you, both front legs up, pumping in turn
    }

    /// What one leg does in a move: stands (lifted `tap` off its spot) or
    /// is up in the air at a place in the sprite.
    private enum GrooveLeg {
        case ground(CGFloat)
        case air(V2)
    }

    /// This frame of the dance, laid over the body — up off its legs, along
    /// the ledge (sprite units), the lean, the head's nod, the abdomen's
    /// swing and tilt, and the squash on the beat. Nothing when it is not
    /// dancing.
    private struct GrooveFrame {
        var up: CGFloat = 0
        var along: CGFloat = 0
        var pitch: CGFloat = 0
        var nod: CGFloat = 0
        var sway: CGFloat = 0
        var tail: CGFloat = 0
        var squash: CGFloat = 0

        static func mix(_ a: GrooveFrame, _ b: GrooveFrame, _ t: CGFloat) -> GrooveFrame {
            GrooveFrame(up: lerp(a.up, b.up, t), along: lerp(a.along, b.along, t), pitch: lerp(a.pitch, b.pitch, t),
                        nod: lerp(a.nod, b.nod, t), sway: lerp(a.sway, b.sway, t), tail: lerp(a.tail, b.tail, t),
                        squash: lerp(a.squash, b.squash, t))
        }
        func scaled(_ k: CGFloat) -> GrooveFrame {
            GrooveFrame(up: up * k, along: along * k, pitch: pitch * k, nod: nod * k, sway: sway * k, tail: tail * k, squash: squash * k)
        }
    }
    private var gf = GrooveFrame()

    /// The beat the dance keeps: the music's, followed closely but eased
    /// into line rather than jumped to, and carried on through a moment's
    /// quiet — a break in the drums does not stop it dead.
    private var grooveBeat: Double = 0
    private var grooveRate: Double = 2
    private var grooveClock = false
    /// Beats to a pulse: one, or two for fast music (it dances half time).
    private var grooveSpan: Double = 1
    /// When it last heard the beat, and how long it has heard it with no
    /// more than a short break.
    private var musicHeardAt: CGFloat = -99
    private var musicFor: CGFloat = 0
    /// Music noticed, since it started: once, with a note.
    private var musicNoticed = false
    /// The dance it always has when music starts, had: after that, another
    /// is just one of the things it might get up to (see `grooveCooldown`).
    private var musicWelcomed = false
    /// The Studio's ▶: a made-up beat to dance to, from `demoBeatFrom`
    /// until `demoBeatUntil`, with no music on.
    private var demoBeatFrom: CGFloat = 0
    private var demoBeatUntil: CGFloat = -1

    /// The beat it hears: the music's, or the Studio's made-up one.
    private var beatHeard: MusicBeat? {
        if let m = music { return m }
        guard t < demoBeatUntil else { return nil }
        return MusicBeat(beat: Double(t - demoBeatFrom) * 2, period: 0.5, energy: 0.7)
    }
    /// How far into the dance it is — 0 standing, 1 dancing — so it comes
    /// into it and out of it rather than cutting.
    private var grooveMix: CGFloat = 0
    /// A little nod along, when it has music on and is not dancing.
    private var vibeMix: CGFloat = 0
    private var grooveMove: GrooveMove = .bob
    private var groovePrev: GrooveMove = .bob
    /// The pulse the move began on; the pulse the dance began on, and how
    /// many it goes on for; winding down.
    private var grooveMoveAt: Double = 0
    private var grooveFrom: Double = 0
    private var groovePulses: Double = 24
    private var grooveEnding = false
    /// A breather after a dance, before the next.
    private var grooveRestUntil: CGFloat = 0
    /// How long it has been wound down, waiting on its feet.
    private var grooveDoneFor: CGFloat = 0
    /// Per leg: how far up into the air a raised leg is (0…1), where it was
    /// last up there, and the spot a standing one holds on the ledge.
    private var grooveAir = Array(repeating: CGFloat(0), count: SpiderRenderer.legCount)
    private var grooveAirAt = Array(repeating: V2.zero, count: SpiderRenderer.legCount)
    private var grooveBase = Array(repeating: V2.zero, count: SpiderRenderer.legCount)
    private var groovePlanted = Array(repeating: false, count: SpiderRenderer.legCount)

    /// How long a step to its spot takes, standing (see `settleFoot`).
    private static let stepTime: CGFloat = 0.26

    /// Tools only: dance this move, whatever it would pick.
    static var debugGrooveMove: String?
    /// Tools only: a dance that goes on as long as the music does.
    static var debugGrooveEndless = false
    /// Tools only: keep a note of what each leg did in the dance.
    static var debugGrooveTrace = false
    private var grooveTrace = Array(repeating: "", count: SpiderRenderer.legCount)
    /// Tools only: how the dance is going.
    var debugGroove: String {
        String(format: "move=%@ mix=%.2f vibe=%.2f pulse=%.2f heard=%.1fs%@", grooveMove.rawValue, grooveMix, vibeMix,
               groovePulse, musicFor, grooveEnding ? " ending" : "")
    }
    /// Tools only: leg `i` in the dance — its foot (sprite), how far up it
    /// is, planted, settling — and the yaw.
    func debugGrooveLeg(_ i: Int) -> String {
        String(format: "foot %.1f,%.1f air %.2f planted %d settle %.2f yaw %.3f ctrl %@ %@", legs[i].foot.x, legs[i].foot.y, grooveAir[i],
               groovePlanted[i] ? 1 : 0, legs[i].settle, yaw, "\(legController)", grooveTrace[i])
    }

    /// Keeps the dance's beat with the music's: on at the music's own rate,
    /// with any drift between them taken out over a fifth of a second or
    /// so. A jump of whole beats is taken in pairs, so the count keeps its
    /// left and right.
    private func followBeat(dt: CGFloat) {
        if let m = beatHeard {
            let rate = 1 / max(m.period, 0.25)
            if !grooveClock {
                grooveBeat = m.beat
                grooveClock = true
            } else {
                grooveBeat += grooveRate * Double(dt)
                var e = m.beat - grooveBeat
                if abs(e) > 1.5 {
                    let jump = 2 * (e / 2).rounded()
                    grooveBeat += jump
                    e -= jump
                }
                grooveBeat += e * Double(min(1, dt * 5))
            }
            grooveRate = rate
            musicFor += dt
            musicHeardAt = t
        } else {
            if grooveClock { grooveBeat += grooveRate * Double(dt) }
            if t - musicHeardAt > 2.5 { musicFor = 0 }
            if t - musicHeardAt > 5 { grooveClock = false }
            if t - musicHeardAt > 8 { musicNoticed = false }
            // Quiet a good while: the next music is new music, and gets a
            // dance as it starts.
            if t - musicHeardAt > 30, musicWelcomed {
                musicWelcomed = false
                grooveRestUntil = min(grooveRestUntil, t)
            }
        }
    }

    /// Music heard steadily enough to dance to.
    private var musicSteady: Bool { musicFor > 3 && grooveClock }

    /// Where the dance is, in pulses.
    private var groovePulse: Double { grooveBeat / grooveSpan }

    /// Whether a pulse starts a bar (the one of four), going by the music.
    private func barStarts(_ pulse: Double) -> Bool {
        let beat = Int(pulse * grooveSpan)
        let bar = beatHeard?.bar ?? 0
        return ((beat - bar) % 4 + 4) % 4 == 0
    }

    /// The music starts: it notices — a note — and, if it is only pottering
    /// about, drops that to dance. Asleep, it wakes up for it first.
    private func noticeMusic() {
        musicNoticed = true
        guard mode == .attached, !dormant, !inCinema else { return }
        setEmote(.note, 1.6)
        happy.velocity = 3
        if activity == .sleep || activity == .rest {
            wake()
            decisionIn = min(decisionIn, 0.4)
            return
        }
        let pottering: Set<Activity> = [.idle, .walk, .sneak, .look, .groom, .fidget, .scratch, .peer, .glance, .stare,
                                         .legStretch, .pushup, .wiggle, .dance, .drum, .wave, .curious, .armsUp, .greet]
        if pottering.contains(activity), laser == nil, huntTarget == nil, toyPlay == nil, homing == nil, build == nil {
            queued = nil
            walkThen = nil
            activity = .idle
            activityTime = 0
            decisionIn = 0.2
        }
    }

    /// The music has just started: a dance, more or less straight away —
    /// unless it is dialled to never dance to music at all. (Kept from
    /// doing it a while by something more pressing, it lets that one go:
    /// after that, dancing is just one of its habits.)
    private var wantsToGroove: Bool {
        mode == .attached && musicSteady && !musicWelcomed && musicFor < 40 && habits.danceMusic > 0.005
            && t >= grooveRestUntil && !inCinema && !dormant
    }

    /// Music still on after a dance: another is in the hat once this has
    /// gone by — a minute or so at the dial's middle, longer for the lazy,
    /// next to nothing with the dial all the way up.
    private var grooveCooldown: CGFloat {
        let often = sqrt(max(1, Habits.weight(habits.danceMusic)))
        return max(3, randRange(40, 90) * lerp(0.7, 1.6, personality.laziness) / often)
    }

    /// Another dance, now the music has been on a while: one of the things
    /// it might do, once the last has had its breather.
    private var mayGrooveAgain: Bool {
        mode == .attached && musicSteady && (musicWelcomed || musicFor >= 40) && t >= grooveRestUntil && !inCinema && !dormant
    }

    /// The moves it can do where it stands: all of them on top of
    /// something; up a side, only those that keep its feet down; hanging
    /// underneath, just the bob.
    private var grooveMoves: [GrooveMove] {
        if surfaceNormal.y > 0.5 { return GrooveMove.allCases }
        if surfaceNormal.y > -0.5 { return [.bob, .pump] }
        return [.bob]
    }

    private func startGroove() {
        guard mode == .attached else { return }
        grooveSpan = grooveRate * 60 > 150 ? 2 : 1
        grooveFrom = groovePulse
        grooveMoveAt = floor(grooveFrom)
        grooveMove = Spider.debugGrooveMove.flatMap { GrooveMove(rawValue: $0) } ?? .bob
        groovePrev = grooveMove
        // A dance: a good long one as the music starts, the playful
        // longer, the lazy less; the ones after, shorter.
        let again: CGFloat = musicWelcomed ? 0.7 : 1
        groovePulses = Double(randRange(24, 48) * again * lerp(0.75, 1.35, personality.playfulness) * lerp(1, 0.6, drowsy))
        musicWelcomed = true
        grooveEnding = false
        for i in legs.indices {
            grooveAir[i] = 0
            groovePlanted[i] = false
        }
        beginActivity(.groove, dur: 9999)
        setEmote(.note, 1.4)
        happy.velocity = 4
    }

    /// The next move, on the bar: never the same twice running, the
    /// showier ones more often when the music is going hard.
    private func nextGrooveMove() -> GrooveMove {
        if let forced = Spider.debugGrooveMove.flatMap({ GrooveMove(rawValue: $0) }) { return forced }
        let P = personality
        let energy = CGFloat(beatHeard?.energy ?? 0.6)
        var options: [(CGFloat, GrooveMove)] = []
        for m in grooveMoves where m != grooveMove {
            switch m {
            case .bob: options.append((lerp(1.4, 0.7, energy), m))
            case .stomp: options.append((1.1, m))
            case .pump: options.append((lerp(0.8, 1.3, energy), m))
            case .peacock: options.append((lerp(0.8, 1.5, energy) * lerp(0.7, 1.3, P.bravery), m))
            case .arms: options.append((lerp(0.8, 1.5, energy) * lerp(0.6, 1.4, P.affection), m))
            }
        }
        let total = options.reduce(0) { $0 + $1.0 }
        guard total > 0 else { return grooveMove }
        var pick = randRange(0, total)
        for (w, m) in options {
            pick -= w
            if pick <= 0 { return m }
        }
        return options.last!.1
    }

    /// The dance's clock, each frame it is dancing: the next move on the
    /// bar at the end of a phrase, and winding down when the music goes
    /// (after a moment's grace) or the dance has gone on long enough.
    private func progressGroove(dt: CGFloat) {
        let q = groovePulse
        let lost = beatHeard == nil && t - musicHeardAt > 2.5
        if !grooveEnding, lost || (q - grooveFrom > groovePulses && !Spider.debugGrooveEndless) || !grooveMoves.contains(grooveMove) {
            grooveEnding = true
        }
        let n = floor(q)
        if !grooveEnding, n - grooveMoveAt >= 8, barStarts(n) || n - grooveMoveAt >= 12 {
            groovePrev = grooveMove
            grooveMove = nextGrooveMove()
            grooveMoveAt = n
            if grooveMove != groovePrev, chance(0.5) { setEmote(.note, 1.1) }
        }
        // Done once it has wound down and its feet are down — or a moment
        // after, whatever a foot is up to (one at the end of a ledge with
        // nowhere to stand is the standing legs' to look after).
        grooveDoneFor = grooveEnding && grooveMix <= 0 ? grooveDoneFor + dt : 0
        let footsore = grooveDoneFor > 0.8
        if grooveEnding, grooveMix <= 0, grooveAir.allSatisfy({ $0 == 0 }), legs.allSatisfy({ $0.settle < 0 }) || footsore {
            grooveRestUntil = t + grooveCooldown
            demoBeatUntil = min(demoBeatUntil, t)
            activity = .idle
            activityTime = 0
            decisionIn = randRange(0.4, 1.2)
        }
    }

    /// Works out this frame of the dance (and of the nodding along), before
    /// the body is placed.
    private func updateGroove(dt: CGFloat) {
        guard mode == .attached, grooveClock else {
            grooveMix = 0
            vibeMix = 0
            gf = GrooveFrame()
            return
        }
        let pulseSecs = CGFloat(grooveSpan / max(grooveRate, 0.5))
        if activity == .groove {
            // In over about a pulse, out over the same.
            let rate = 1 / max(pulseSecs * 1.2, 0.35)
            grooveMix = grooveEnding ? max(0, grooveMix - dt * rate) : min(1, grooveMix + dt * rate)
        } else {
            grooveMix = max(0, grooveMix - dt * 5)
        }
        let nodding: Set<Activity> = [.idle, .look, .rest, .watch, .stare, .glance, .groom, .eat]
        let vibe = musicFor > 1.2 && beatHeard != nil && activity != .groove && nodding.contains(activity)
        vibeMix = approach(vibeMix, vibe ? 1 : 0, 3, dt)

        let q = groovePulse
        var g = GrooveFrame()
        if grooveMix > 0 {
            let blend = smoothstep(clamp(CGFloat(q - grooveMoveAt), 0, 1))
            g = grooveBody(grooveMove, q)
            if blend < 1 { g = GrooveFrame.mix(grooveBody(groovePrev, q), g, blend) }
            let energy = CGFloat(beatHeard?.energy ?? 0.6)
            g = g.scaled(smoothstep(grooveMix) * lerp(0.8, 1.2, energy))
        }
        if vibeMix > 0 {
            // Just the head, going with the beat.
            let f = CGFloat(q - floor(q))
            g.nod += -0.11 * vibeMix * sin(.pi * min(f / 0.45, 1))
        }
        gf = g
    }

    /// Where a pulse is: which one (even ones and odd ones alternate left
    /// and right), and how far through it, 0 on its beat.
    private static func pulseAt(_ q: Double) -> (even: Bool, f: CGFloat) {
        let n = floor(q)
        return (Int(n) & 1 == 0, CGFloat(q - n))
    }

    /// The body in a move, `q` pulses in. Everything lands on the beat: the
    /// body comes down onto its legs with a bounce whose bottom is the beat
    /// itself, and whatever swings from side to side speeds up into its
    /// new side and stops there on the beat.
    private func grooveBody(_ m: GrooveMove, _ q: Double) -> GrooveFrame {
        let (even, f) = Spider.pulseAt(q)
        let side: CGFloat = even ? 1 : -1
        // Up off the legs, the bottom of it right on the beat.
        let bounce = pow(sin(.pi * f), 0.8) - 0.3
        // From this pulse's side over to the next's, arriving on the beat.
        func swap(_ amp: CGFloat) -> CGFloat { lerp(side * amp, -side * amp, pow(f, 2.2)) }
        var g = GrooveFrame()
        g.squash = 0.06 * pow(1 - f, 5)
        // The head goes on down a moment after the body stops, and back.
        g.nod = -0.16 * sin(.pi * min(f / 0.45, 1))
        switch m {
        case .bob:
            g.up = 5.5 * bounce
            g.pitch = 0.05 * bounce
            g.sway = swap(2.3)
        case .stomp:
            // Rocking onto whichever feet are down.
            g.up = 3.2 * bounce
            g.pitch = swap(0.07)
            g.sway = swap(1.6)
            g.nod *= 1.25
        case .pump:
            g.up = 3.6 * bounce
            g.pitch = 0.05 + swap(0.035)
            g.sway = swap(1.3)
        case .peacock:
            // Up on its toes, tipped a little forward with the abdomen
            // raised high behind, shifting its weight from side to side
            // every other pulse — the peacock spider's display.
            let (even2, f2) = Spider.pulseAt(q / 2)
            let side2: CGFloat = even2 ? 1 : -1
            g.up = 2 + 2.6 * bounce
            g.pitch = -0.06
            g.tail = -0.36 + 0.08 * bounce
            g.sway = swap(2.4)
            g.along = lerp(side2 * 2.6, -side2 * 2.6, pow(f2, 2.2))
            g.nod *= 0.8
        case .arms:
            g.up = 1.5 + 4 * bounce
            g.nod *= 0.7
        }
        return g
    }

    /// What leg `i` does in a move, `q` pulses in.
    private func grooveLeg(_ m: GrooveMove, _ i: Int, _ q: Double) -> GrooveLeg {
        let k = i % 4, near = i < 4
        let (even, f) = Spider.pulseAt(q)
        let hip = legs[i].hip, rest = legs[i].rest
        /// A foot that comes down on every other beat — on the even pulses
        /// or the odd ones — lifted through the pulse before, slowly up and
        /// sharply down.
        func stamp(onEven: Bool, _ h: CGFloat) -> CGFloat {
            guard even != onEven else { return 0 }
            return h * sin(.pi * pow(f, 1.4))
        }
        /// Between two places, one this pulse and the other the next, in
        /// turn, arriving on the beat: `upFirst` has it at `a` on the even
        /// pulses.
        func pump(_ a: V2, _ b: V2, upFirst: Bool) -> V2 {
            let atA = even == upFirst
            return Spider.swing(atA ? a : b, atA ? b : a, about: hip, pow(f, 2))
        }
        switch m {
        case .bob:
            return .ground(k == 0 ? stamp(onEven: near, 6) : 0)
        case .stomp:
            let first = [0, 2, 5, 7].contains(i)
            return .ground(stamp(onEven: first, k == 0 ? 8 : 10))
        case .pump:
            // Out in front of the face and up, clear of the eyes, with the
            // knee out in front like an elbow, and back down to just off
            // the ledge.
            guard k == 0 else { return .ground(0) }
            legBend[i] = V2(1, -0.5)
            let up = near ? V2(30, 20) : V2(27, 23)
            return .air(pump(up, V2(rest.x + 3, rest.y + 7), upFirst: near))
        case .peacock:
            // Fanned up behind the raised abdomen, the two in turn: the
            // thigh back under it and the shin up behind it.
            guard k == 3 else { return .ground(0) }
            legBend[i] = V2(-0.2, -1)
            let high = near ? V2(-31, 12) : V2(-26, 18)
            let low = near ? V2(-35, 1) : V2(-31, 7)
            return .air(pump(high, low, upFirst: near))
        case .arms:
            // As in a greeting, face on: the inner pair beside the head, the
            // outer pair out to the sides, standing on the four behind.
            if i == 1 || i == 2 {
                let side: CGFloat = i == 1 ? 1 : -1
                let atTop = even == (i == 1)
                let e = pow(f, 2)
                let up = atTop ? lerp(38, 19, e) : lerp(19, 38, e)
                let out = atTop ? lerp(20, 25, e) : lerp(25, 20, e)
                return .air(faceOnRaise(i, side: side, out: out, up: up))
            }
            if let out = faceOnOuter(i) { return .air(out) }
            return .ground(0)
        }
    }

    /// The legs, dancing: a raised one swung up into the air and moved as
    /// the move has it; a standing one held where it stands on the ledge
    /// while the body bounces over it — lifted off it and brought down on
    /// the beat, in the moves that stamp — and stepping only when it is
    /// left well off where it should stand (turned to face you, say).
    private func updateGrooveLegs(dt: CGFloat, dTheta: CGFloat, overFeet: V2) {
        let q = groovePulse
        let handing = clamp(CGFloat(q - grooveMoveAt), 0, 1)
        let blend = smoothstep(handing)
        let winding = grooveEnding ? grooveMix : min(1, grooveMix * 1.5)
        // Into the dance and out of it, a leg goes up or comes down over a
        // pulse or so. (Between moves, over the pulse the one hands over to
        // the next in, arriving on the beat.)
        let swingTime = clamp(CGFloat(grooveSpan / max(grooveRate, 0.5)), 0.3, 0.6)
        // Winding down, the feet step right onto their spots, so none is
        // left to be slid there once it stops.
        let slack = grooveEnding ? Spider.plantTidy : Spider.plantSlack
        for i in legs.indices {
            var leg = legs[i]
            leg.footVel = .zero
            let stand = groundPose(i, standingFoot(i, braced: false))
            // Where the foot stands — or stood before it went up, or will
            // come down — held on the ledge as the body moves over it.
            if groovePlanted[i] {
                grooveBase[i] = grooveBase[i].rotated(by: -dTheta) - overFeet
            } else {
                grooveBase[i] = leg.foot.rotated(by: -dTheta) - overFeet
                groovePlanted[i] = true
            }
            var want = grooveLeg(grooveMove, i, q)
            // How far up a leg going up or coming down with a change of
            // move is: all the way by the beat that ends the hand-over.
            var goal: CGFloat = 1
            if blend < 1 {
                switch (grooveLeg(groovePrev, i, q), want) {
                case let (.ground(a), .ground(b)): want = .ground(lerp(a, b, blend))
                case let (.air(a), .air(b)): want = .air(Spider.swing(a, b, about: leg.hip, blend))
                // (Eased once, as it swings: see below.)
                case (.ground, .air): goal = handing
                case (.air(let a), .ground): want = .air(a); goal = 1 - handing
                }
            }
            // Winding down, a raised leg comes back to the ledge (a stamping
            // one stamps less and less, with the rest of the dance).
            if grooveEnding, case .air = want { want = .ground(0) }

            switch want {
            case .air(let target):
                if grooveAir[i] == 0 { leg.settle = -1 }
                grooveAir[i] = goal >= grooveAir[i] ? min(goal, grooveAir[i] + dt / swingTime)
                                                    : max(goal, grooveAir[i] - dt / swingTime)
                grooveAirAt[i] = target
                // Well off the ledge, the spot it will come down on drifts to
                // where it should stand — in the air, not dragged over the
                // ground as it lifts.
                if grooveAir[i] > 0.3 { grooveBase[i] = approach(grooveBase[i], stand, 10 * smoothstep((grooveAir[i] - 0.3) / 0.4), dt) }
                leg.foot = Spider.swing(grooveBase[i], target, about: leg.hip, smoothstep(grooveAir[i]))
                leg.lift = grooveAir[i]
            case .ground(let rawTap):
                if grooveAir[i] > 0 {
                    // Coming down out of the air onto its spot.
                    grooveAir[i] = max(0, grooveAir[i] - dt / swingTime)
                    if grooveAir[i] > 0.3 { grooveBase[i] = approach(grooveBase[i], stand, 10 * smoothstep((grooveAir[i] - 0.3) / 0.4), dt) }
                    leg.foot = Spider.swing(grooveBase[i], grooveAirAt[i], about: leg.hip, smoothstep(grooveAir[i]))
                    leg.lift = grooveAir[i]
                    if grooveAir[i] == 0 { leg.foot = grooveBase[i]; leg.lift = 0 }
                    break
                }
                if leg.settle >= 0 {
                    // A step to its spot, under way.
                    _ = settleFoot(&leg, i, to: leg.settleTo, dt: dt)
                    grooveBase[i] = leg.foot
                    break
                }
                let tap = rawTap * winding
                // (A step only from a foot that is down, and that the move
                // leaves down for as long as the step takes — never out of
                // or into a stamp.)
                let off = grooveBase[i].distance(to: stand)
                let floating = grooveBase[i].distance(to: groundFoot(grooveBase[i])) > 1.5
                let busy = legs.indices.contains { $0 != i && legs[$0].settle >= 0 }
                let stepPulses = Double(Spider.stepTime) / (grooveSpan / max(grooveRate, 0.5))
                var downLong = tap < 0.5
                if downLong, case .ground(let later) = grooveLeg(grooveMove, i, q + stepPulses) { downLong = later * winding < 0.5 }
                if downLong, floating || (off > slack && (!busy || off > Spider.plantSlack * 2)) {
                    leg.foot = grooveBase[i] + V2(0, tap)
                    leg.settle = 0
                    leg.swingFrom = leg.foot
                    leg.settleTo = stand
                    _ = settleFoot(&leg, i, to: stand, dt: dt)
                    grooveBase[i] = leg.foot
                    break
                }
                leg.foot = grooveBase[i] + V2(0, tap)
                leg.lift = clamp(tap / 4, 0, 1)
                if Spider.debugGrooveTrace { grooveTrace[i] = String(format: "tap %.2f raw %.2f blend %.2f moves %@>%@", tap, rawTap, blend, groovePrev.rawValue, grooveMove.rawValue) }
            }
            legs[i] = leg
        }
    }

    // MARK: Peek-a-boo

    /// Edges to hide behind on the segment it is on: where a window in
    /// front of its surface crosses the segment. `into` is the direction
    /// along the segment that leads behind the window.
    private func hidingEdges() -> [(t: CGFloat, into: CGFloat)] {
        // Only a window's edge can be behind another window; on the screen's
        // rim it is always in front, so there is nothing there to hide behind.
        guard mode == .attached, let loop = map.loop(anchor.loopID), loop.kind.onWindow,
              anchor.segIdx < loop.segs.count else { return [] }
        let seg = loop.segs[anchor.segIdx]
        var out: [(CGFloat, CGFloat)] = []
        for o in map.occluders where o.depth < loop.depth {
            guard let span = seg.span(inside: o.rect) else { continue }
            // A window must cover a decent stretch, and leave room in front.
            guard span.1 - span.0 > 50 * config.scale else { continue }
            if span.0 > 70 * config.scale { out.append((span.0, 1)) }
            if span.1 < seg.len - 70 * config.scale { out.append((span.1, -1)) }
        }
        return out
    }

    /// Starts a game if there is an edge within `reach` along this segment.
    @discardableResult
    private func startPeekaboo(reach: CGFloat) -> Bool {
        guard mode == .attached, !inCinema, caught == nil else { return false }
        let edges = hidingEdges().filter { abs($0.t - anchor.t) < reach }
        guard let e = edges.min(by: { abs($0.t - anchor.t) < abs($1.t - anchor.t) }) else { return false }
        peek = Peek(edgeT: e.t, into: e.into, wanted: Int.random(in: 2...4))
        beginActivity(.peekaboo, dur: 60)
        queued = nil
        remember(.played, 0.5)
        return true
    }

    /// Asked to play (the menu): here if it can, else off to find an edge.
    func playPeekaboo() {
        wake()
        if startPeekaboo(reach: 900) { return }
        wantsPeekabooUntil = t + 40
        goHideSomewhere()
    }

    /// Nowhere to hide on this edge: leap to a surface that has a window
    /// crossing it, or wander and look again.
    private func goHideSomewhere() {
        guard mode == .attached else { return }
        var best: (d: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) where spot.loop.id != anchor.loopID {
            let crossed = map.occluders.contains { $0.depth < spot.loop.depth && spot.seg.span(inside: $0.rect) != nil }
            guard crossed, spot.point.distance(to: pos) > 60 else { continue }
            guard let launch = ballistic(from: pos, to: spot.point), launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
            let d = spot.point.distance(to: pos)
            if best == nil || d < best!.d { best = (d, spot.point) }
        }
        if let b = best { startJump(to: b.point) } else { turnTo(wanderWay(), then: .walk, for: randRange(1.5, 3)) }
    }

    private func progressPeekaboo(dt: CGFloat) {
        guard var pk = peek, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else {
            peek = nil
            activity = .idle
            return
        }
        let seg = loop.segs[anchor.segIdx]
        let sc = config.scale
        pk.stageTime += dt
        // Where each stage wants it along the edge.
        let hideT = pk.edgeT + pk.into * 38 * sc          // right behind the window
        let popT = pk.edgeT - pk.into * 10 * sc           // out just far enough for its head
        let brinkT = pk.edgeT - pk.into * 22 * sc         // nose at the edge
        var goal: CGFloat
        var pace: CGFloat
        switch pk.stage {
        case 0: goal = brinkT; pace = config.walkSpeed * 0.6
        case 1: goal = hideT; pace = config.walkSpeed * 0.9
        case 3: goal = popT; pace = config.walkSpeed * 1.8
        default: goal = anchor.t; pace = 0
        }
        goal = clamp(goal, 4, seg.len - 4)
        let diff = goal - anchor.t
        if pace > 0, abs(diff) > 3 {
            // The ordinary walk carries it there; it just steers and paces.
            walkDir = diff >= 0 ? 1 : -1
            facing = walkDir
            peekPace = min(pace, abs(diff) * 6)
        } else {
            peekPace = 0
            speed = 0
            // At the mark: on to the next stage.
            switch pk.stage {
            case 0:
                pk.stage = 1; pk.stageTime = 0
            case 1:
                pk.stage = 2; pk.stageTime = 0
            case 2:
                if pk.stageTime > randRange(0.9, 2.2) {
                    pk.stage = 3; pk.stageTime = 0
                    // Boo!
                    setEmote(chance(0.5) ? .surprise : .sparkle, 0.9)
                    happy.velocity = 6
                    startled.velocity = 3
                    stretch.velocity = 4
                }
            case 3:
                pk.stage = 4; pk.stageTime = 0
                pk.pops += 1
                // Face you while it is out.
                facing = cursor.x >= pos.x ? 1 : -1
                walkDir = facing
            default:
                if pk.stageTime > randRange(0.8, 1.8) {
                    if pk.pops >= pk.wanted {
                        peek = nil
                        beginActivity(.wiggle, dur: randRange(0.8, 1.4))
                        happy.velocity = 8
                        return
                    }
                    pk.stage = 1; pk.stageTime = 0
                }
            }
        }
        peek = pk
    }

    // MARK: The box

    /// Nothing to stand on in its box: it hangs on a line from the top of
    /// it, and stays on that line whatever happens.
    private func keepHung(dt: CGFloat) {
        guard hangOnly, let box = confine, !isHeld else { return }
        let top = V2(box.midX, box.maxY - 4)
        if mode == .dangling, webActive { return }
        // Well away from it (thrown, say): it makes its way back first, and
        // only takes to the line once it is close, so the line never has to
        // haul it in from across the room.
        guard box.insetBy(dx: -160, dy: -160).contains(pos.point) else { return }
        if mode == .nesting { leaveNest(startled: false) }
        // Falling, or somehow on something: onto the line.
        if mode == .attached { anchorValid = false }
        pos = V2(clamp(pos.x, box.minX + 10, box.maxX - 10), clamp(pos.y, box.minY + 10, box.maxY - 10))
        vel = vel.clampedLength(200)
        attachWeb(at: top)
        hungSince = t
        webStyle = .hang
        swingPumping = false
        webLenTarget = clamp(box.height * randRange(0.35, 0.55), 30, 780)
        decisionIn = randRange(3, 8)
    }

    private func inBoxOrFree(_ p: V2) -> Bool { confine.map { $0.contains(p.point) } ?? true }

    /// How far it is along a loop from here (or from `start`) to `target`
    /// going `dir`, or nil if a blocked stretch (a window in front) is in
    /// the way.
    private func loopDistance(_ loop: SurfaceLoop, to target: Anchor, dir: CGFloat, from start: Anchor? = nil) -> CGFloat? {
        let n = loop.segs.count
        let from = start ?? anchor
        guard target.segIdx < n, from.segIdx < n else { return nil }
        var idx = from.segIdx
        var t = from.t
        var total: CGFloat = 0
        for _ in 0...n {
            let seg = loop.segs[idx]
            let end: CGFloat = idx == target.segIdx && (total > 0 || (dir > 0 ? target.t >= t : target.t <= t)) ? target.t : (dir > 0 ? seg.len : 0)
            let lo = min(t, end), hi = max(t, end)
            if seg.blocked.contains(where: { $0.lo < hi - 0.01 && $0.hi > lo + 0.01 }) { return nil }
            total += hi - lo
            if idx == target.segIdx, end == target.t { return total }
            let next = idx + (dir > 0 ? 1 : -1)
            guard loop.closed || (next >= 0 && next < n) else { return nil }
            idx = (next + n) % n
            t = dir > 0 ? 0 : loop.segs[idx].len
        }
        return nil
    }

    /// Outside its patch: heads back in — along its own edge if that leads
    /// there, else a leap to the nearest spot inside it can reach, else a
    /// walk toward it and another try next time. Out for a long while, it
    /// is fetched.
    private func returnToBox() {
        guard let box = confine, mode == .attached else { return }
        if outOfBoxSince < 0 { outOfBoxSince = t }
        if t - outOfBoxSince > 90 {
            outOfBoxSince = -1
            teleport(to: V2(box.midX, box.maxY - 20))
            return
        }
        decisionIn = randRange(0.5, 1.2)
        let centre = V2(box.midX, box.midY)
        let inside = map.sampleSpots(spacing: 40).filter { box.contains($0.point.point) }
        if ProcessInfo.processInfo.environment["SPIDER_DEBUG_BOX"] == "1" {
            let same = inside.filter { $0.loop.id == anchor.loopID }.count
            print("box: at \(Int(pos.x)),\(Int(pos.y)) on \(anchor.loopID) seg \(anchor.segIdx) t \(Int(anchor.t)); inside spots \(inside.count) (same loop \(same)); loops in box: \(Set(inside.map { $0.loop.id }).sorted())")
        }
        // On an edge that runs into the box: walk round to the nearest bit
        // of it that is inside, whichever way round is open and shorter.
        if let loop = map.loop(anchor.loopID) {
            var best: (d: CGFloat, dir: CGFloat, point: V2)?
            for spot in inside where spot.loop.id == anchor.loopID {
                for dir in [CGFloat(1), -1] {
                    if let d = loopDistance(loop, to: spot.anchor, dir: dir), best == nil || d < best!.d {
                        best = (d, dir, spot.point)
                    }
                }
            }
            if let b = best {
                if b.d < 30 { walkToward(b.point) } else { turnTo(b.dir, then: .walk, for: clamp(b.d / max(config.walkSpeed, 1), 1.0, 4.0)) }
                return
            }
        }
        var best: (d: CGFloat, point: V2)?
        for spot in inside {
            guard spot.point.distance(to: pos) > 40 else { continue }
            guard let launch = ballistic(from: pos, to: spot.point), launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
            let d = spot.point.distance(to: pos)
            if best == nil || d < best!.d { best = (d, spot.point) }
        }
        if let b = best {
            startJump(to: b.point)
            return
        }
        // Nothing inside to land on (or none in reach): whatever gets it
        // nearer — the nearest reachable spot to the box, or a walk that way.
        var nearer: (d: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) {
            let d = spot.point.distance(to: centre)
            guard d < pos.distance(to: centre) - 40, spot.point.distance(to: pos) > 50 else { continue }
            guard let launch = ballistic(from: pos, to: spot.point), launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
            if nearer == nil || d < nearer!.d { nearer = (d, spot.point) }
        }
        if let nr = nearer, chance(0.7) {
            startJump(to: nr.point)
        } else {
            walkToward(centre)
        }
    }

    /// Takes it easy in the box: the odd stretch and yawn on the line, a
    /// little up and down, never a swing.
    private func thinkHung() {
        guard let box = confine else { return }
        decisionIn = randRange(4, 11) / max(config.liveliness * 0.6, 0.2)
        let roll = CGFloat.random(in: 0...1)
        if roll < 0.35 {
            // Shifts its height a little.
            webLenTarget = clamp(webLen + randRange(-70, 70), 30, max(30, box.height - 60))
        } else if roll < 0.5 {
            webAngleVel += randRange(-0.1, 0.1)
        } else if roll < 0.6 {
            bungee.velocity = randRange(80, 140) * (chance(0.5) ? 1 : -1)
        }
        // Otherwise: hangs there, content.
    }

    // MARK: Moving house

    /// Fires a line up at `point` (the underside of the habitat window,
    /// say), hauls itself up it, and calls `done` when it gets to the top.
    /// Needs to be standing on something; returns false if it is not.
    private var climbArrival: (() -> Void)?
    @discardableResult
    func climbAway(to point: V2, then done: @escaping () -> Void) -> Bool {
        guard mode == .attached, point.y > pos.y + 30 else { return false }
        climbArrival = done
        wake()
        queued = nil
        pendingJump = nil
        huntTarget = nil
        shotTarget = point
        shotPurpose = .climb
        shotProgress = 0
        beginActivity(.shoot, dur: 0.25)
        return true
    }

    /// Drops in from `p` in mid-air and falls onto
    /// whatever is below.
    func dropIn(at p: V2) {
        teleport(to: p)
    }

    // MARK: The habitat

    /// The line being climbed goes up into the habitat: nothing on the
    /// desktop can come between it and the top.
    private var tankClimb = false
    /// On its way up a line to somewhere (the habitat, say).
    var isClimbingAway: Bool { climbArrival != nil }

    /// Fires a line up at `point` — the lip of the habitat's ground — and
    /// hauls itself up it; `arrived` is called as it gets to the top.
    /// Needs to be standing on something below the point.
    @discardableResult
    func climbIntoHabitat(at point: V2, arrived: @escaping () -> Void) -> Bool {
        guard mode == .attached, !isHeld, point.y > pos.y + 40 else { return false }
        abandonBuild()
        wake()
        homing = nil
        tankClimb = true
        climbArrival = arrived
        queued = nil
        pendingJump = nil
        huntTarget = nil
        shotTarget = point
        shotPurpose = .climb
        shotProgress = 0
        beginActivity(.shoot, dur: 0.3)
        return true
    }

    /// At the top of its line into the habitat: onto the habitat's map,
    /// and up over the lip in a little hop onto the ground at `target`.
    func hopIntoHabitat(map newMap: SurfaceMap, landing target: V2) {
        climbArrival = nil
        tankClimb = false
        detachWeb(fade: false)
        webAlpha.reset(0)
        rope.clear()
        moveInMidAir(map: newMap, habitat: true)
        // Up to a little over the ground and down onto it: the rise is
        // left alone, so it cannot catch the ground from underneath.
        let g = -gravity.y
        let apex = max(target.y, pos.y) + 30 * config.scale
        let vy = (2 * g * max(apex - pos.y, 4)).squareRoot()
        let rise = vy / g
        let fall = (2 * max(apex - target.y, 1) / g).squareRoot()
        mode = .airborne
        air = .jump
        airTime = 0
        vel = V2((target.x - pos.x) / (rise + fall), vy)
        noAttachFor = rise + 0.02
        launchLoop = ""
        anchorValid = false
        if let spot = map.nearestSpot(to: target, within: 60 * config.scale) {
            landing = (spot.point, spot.seg.angle, spot.seg.dir)
        }
        legMode = .free
        activity = .idle
        crouch.velocity = -6
        stretch.velocity = 5
        happy.velocity = 6
        setEmote(.sparkle, 1.0)
        decisionIn = randRange(1.0, 1.6)
    }

    /// Lets go of whatever it is standing on and drops (down to where it
    /// can get at the habitat from).
    func dropOff() {
        guard mode == .attached, !isHeld else { return }
        wake()
        queued = nil
        pendingJump = nil
        let wall = abs(surfaceNormal.x) > 0.7 ? surfaceNormal : nil
        detachAndFall()
        // Off a wall it kicks away from it, or it would only grab the same
        // wall again on the way down.
        if let n = wall, mode == .airborne {
            vel += V2(n.x * 170, 60)
            noAttachFor = 0.35
            draglineCatchY = nil
            webActive = false
        }
    }

    /// Put straight into the habitat, standing on its ground at `p` —
    /// where it was when the app last quit.
    func placeInHabitat(map newMap: SurfaceMap, at p: V2) {
        enter(map: newMap, at: p, habitat: true)
        if let spot = map.nearestSpot(to: p, within: 400) {
            pos = spot.point + spot.seg.normal * 2
            vel = V2(0, -60)
        }
        emote = .none
    }

    /// The habitat has gone from round it: back on `newMap` (the desktop)
    /// at the very spot it was, and it drops from there — whatever it was
    /// standing on, or hanging from, went with the tank.
    func dropOutOfHabitat(onto newMap: SurfaceMap) {
        tankClimb = false
        pendingMap = nil
        moveInMidAir(map: newMap, habitat: false)
        climbArrival = nil
        guard !isHeld, mode != .airborne else { return }
        abandonBuild()
        detachWeb(fade: false)
        webAlpha.reset(0)
        rope.clear()
        webPlan = []
        mode = .airborne
        air = .fall
        vel = V2(0, -30)
        airTime = 0
        noAttachFor = 0.12
        launchLoop = ""
        anchorValid = false
        legMode = .free
        activity = .idle
        queued = nil
        pendingJump = nil
        startled.velocity = 6
        setEmote(.surprise, 0.6)
        planFall(from: nil)
    }

    /// Its first arrival on the desktop: out of the menu bar icon it lives
    /// in and down on a line from there — a look round its new home from
    /// the end of the thread, then on down to the floor or off onto
    /// something, and from then on it is its own spider.
    func enterOnThread(from a: V2) {
        wake()
        isHeld = false
        pendingJump = nil
        queued = nil
        // Head down, its spinnerets a little way under the icon.
        vel = .zero
        heading = -.pi / 2 + (facing < 0 ? .pi : 0)
        headingTarget = heading
        headingVel = 0
        yaw = facing
        pos = a + V2(0, -20) - (toWorld(spinnerets) - pos)
        attachWeb(at: a)
        webStyle = .hang
        webLen = 20
        webLenTarget = webLen
        bungee.reset(0)
        prevHangLen = webLen
        legFramePos = pos
        legFrameHeading = heading
        kneeShape = []
        footWorld = []
        let screen = map.screenFrame(containing: a)
        let room = max(60, a.y - (screen.minY + 30 * config.scale))
        let first = clamp(randRange(170, 260) * config.scale, 60, room)
        webPlan = [.descend(first), .linger(randRange(2.2, 3.4)), chance(0.6) && room < 760 ? .toFloor : .jumpOff]
        webLenTarget = first
        decisionIn = randRange(0.3, 0.6)
        happy.velocity = 6
        setEmote(.sparkle, 1.2)
    }

    // MARK: Things in the tank
    //
    // What the things in the tank are to it (HabitatSemantics.swift), and
    // how it gets to know them (HabitatKnowledge.swift).
    //
    // Something new in the tank is no news to it until it notices it: sooner
    // the nearer and bigger it is and the more it moves (dropped in beside
    // it, it all but always does), hardly at all asleep or busy, and the
    // curious sooner than the rest. Then it stops and looks. When it is free,
    // and feels like it, it looks into it: from a distance first, then closer
    // — a timid one in stages, stopping to watch, backing off if the thing so
    // much as moves; a bold one straight up to it — and then whatever the
    // thing's shape offers: a feel of it with its front legs, the other side
    // of it, a look under it or into it or at its water, partway up it, up
    // onto the top of it by its own surfaces (or, a bold one, with a leap),
    // before it settles near it — or on it — watching a while. Time near it
    // with nothing going wrong, and each thing it finds out about it, make it
    // familiar; and a familiar thing is only part of the tank.
    //
    // Decorating round it: something big put down right by it gives it a
    // start, and it backs off to watch; something small it goes to see;
    // something moved it sees move; a whole rearrangement has it out
    // exploring for a while after. Standing on something that is picked up
    // and carried off, it holds on and goes with it (`thingsCarried`), and
    // takes its footing on it again where it is put down.

    /// The tank as it stands (see `tankRebuilt`), and what it knows of the
    /// things in it (the app keeps that). Without both — as in the tools,
    /// unless they give it them — none of this happens at all.
    private(set) var tank: Habitat?
    var knowledge: HabitatKnowledge?

    /// What there is to find out about a thing, one go at a time.
    private enum Probe: String {
        case feel, peer, water, beneath, inside, otherSide, partway, top, leapOn
    }
    private enum InquiryStage: String { case orient, watch, approach, retreat, probe, linger }
    /// Looking into something.
    private struct Inquiry {
        var uid: String
        var stage: InquiryStage = .orient
        var since: CGFloat
        var stageSince: CGFloat
        /// What it means to find out about it, in order, and what it has.
        var todo: [Probe]
        var done: [Probe] = []
        /// Where the go under way is had from.
        var at: InteractionPoint?
        /// Set about it (not just getting there), and how far into it.
        var doing = false
        var step = 0
        /// How near it will come to it just now.
        var comfort: CGFloat
        var watchFor: CGFloat = 0
        var watches = 0
        /// A leg of a staged approach is done: a stop to watch, next.
        var pause = false
        var retreats = 0
        var stalls = 0
        /// Set off toward where the next go is had, from `lastPos`.
        var went = false
        var lastPos = V2.zero
        var lingerFor: CGFloat = 0
        /// Which side of it it is working from (-1 its left, 1 its right).
        var side: CGFloat = 1
    }
    private var inquiry: Inquiry?
    private var inquiryRestUntil: CGFloat = 0
    /// Noticed just now: the first to look into, when next it is free.
    private var freshlyNoticed: String?
    /// What in the tank it has its eyes on, and until when: its head and
    /// eyes go to it as they would to the pointer.
    private var eyeOn: V2?
    private var eyeOnUntil: CGFloat = -1
    /// On its way somewhere: the walk stops once it is within `within` of it.
    private var walkGoal: (anchor: Anchor, within: CGFloat)?
    /// ...and where it goes over from the surface it is on onto the next.
    private var routeHop: SurfaceJunction?
    /// Gone over onto the next surface of the way this frame.
    private var crossedHop = false
    /// Things it has just seen move — put in, carried about — by `id`:
    /// until when, and how much.
    private var stirring: [Int: (until: CGFloat, amount: CGFloat)] = [:]
    private var senseIn: CGFloat = 0
    /// After the tank is rearranged, it is out exploring until then.
    private var exploreUntil: CGFloat = -99
    private var changesAt: [CGFloat] = []
    /// The thing under its feet (its `id`), as of the last frame.
    private var underfoot: Int?
    /// Standing on something being carried about: which, and how far it has
    /// come since the surfaces were last laid out (they are laid out again
    /// only when it is put down).
    private var riding: Int?
    private var rideShift = V2.zero
    /// Where each thing being carried was last told to be.
    private var carriedAt: [Int: V2] = [:]
    /// What its front legs are feeling (`.feel`), and which way that faces.
    private var feelAt: V2?
    private var feelNormal = V2(0, 1)

    private var exploring: Bool { t < exploreUntil }

    /// How big, for its own size, a thing is to be a fright dropped by it
    /// (its size across over about its own length).
    private static let bigThing: CGFloat = 2

    /// The back wall's hardware and the rooms' back walls are nothing to it.
    private func worthKnowing(_ it: HabitatItem) -> Bool {
        !it.kind.isBacking && it.kind.definition.layer != .rear && it.kind.definition.shelf != .walls
    }

    /// How far it is to the nearest of it.
    private func distance(to it: HabitatItem) -> CGFloat {
        let r = it.rect
        return V2(max(r.minX - pos.x, 0, pos.x - r.maxX), max(r.minY - pos.y, 0, pos.y - r.maxY)).length
    }

    /// Where it looks at it: toward the middle of it, from its near side.
    private func focusPoint(_ it: HabitatItem) -> V2 {
        let r = it.rect
        return V2.lerp(V2(clamp(pos.x, r.minX, r.maxX), clamp(pos.y, r.minY, r.maxY)), V2(r.midX, r.midY), 0.6)
    }

    /// Eyes on `p` for a while.
    private func look(at p: V2, for secs: CGFloat) {
        eyeOn = p
        eyeOnUntil = max(eyeOnUntil, t + secs)
    }

    /// How much it has its wits about it: asleep hardly at all, busy with
    /// something else less, looking about the most.
    private var alertness: CGFloat {
        if dormant || activity == .sleep || mode == .nesting { return 0.08 }
        if mode != .attached { return 0.6 }
        if caught != nil || activity == .eat { return 0.3 }
        if huntTarget != nil || laser != nil || cursorHunt != .none { return 0.25 }
        if toyPlay != nil { return 0.45 }
        switch activity {
        case .rest, .bask, .watch, .brace, .drink: return 0.6
        case .look, .stare, .peer, .glance, .feel: return 1.3
        case .walk, .sneak: return 1.1
        case .scurry: return 0.7
        default: return 1
        }
    }

    /// The tank's surfaces were laid out again (see
    /// `HabitatSceneView.rebuildMap`), or it is shown the tank for the first
    /// time. What it knows is brought up to date; and in it (`inIt`) it takes
    /// its footing again — `smooth`: the same surfaces, reshaped (a door
    /// swung), so it carries on as it was — and takes in what has changed.
    /// `survey`: its places, sized up already on these surfaces (off the
    /// main thread) for `tankMap`; without one they are sized up when next
    /// wanted.
    /// `ways`: the tank's ways for `tankMap`'s surfaces, worked out already;
    /// `waysComing`: the tank is working them out, to hand over soon.
    func tankRebuilt(_ h: Habitat, smooth: Bool, inIt: Bool, survey sv: PlaceSurvey? = nil, of tankMap: SurfaceMap? = nil,
                     ways: TankNav? = nil, waysComing: Bool = false) {
        let old = tank
        tank = h
        knowledge?.meet(h)
        // (An errand under way finds its place as it is now.)
        survey = sv
        surveyMap = sv != nil ? tankMap.map { ObjectIdentifier($0) } : nil
        // (And the ways about it: a trip under way is planned afresh.)
        if let ways, let tankMap { waysWorkedOut(ways, for: tankMap) } else { navComing = waysComing ? t : nil }
        navTrip = nil
        navLive = false
        placeAt = nil
        if errand != nil { errand!.stale = true }
        guard inIt else {
            riding = nil
            rideShift = .zero
            return
        }
        let change = old.map { HabitatChange(from: $0, to: h) } ?? HabitatChange()
        // (A walk to somewhere on the old surfaces is over: it decides again.)
        if walkGoal != nil || routeHop != nil, [.walk, .sneak, .scurry].contains(activity) { activityDur = min(activityDur, activityTime) }
        walkGoal = nil
        routeHop = nil
        if smooth { surfacesRestructured() } else { retakeFooting(change) }
        riding = nil
        rideShift = .zero
        carriedAt = [:]
        if old != nil, !change.isEmpty, knowledge != nil { takeIn(change) }
    }

    /// Decorating: things being carried about, each `offset` from where it
    /// was when the surfaces were last laid out. It sees them move; standing
    /// on one it holds on and goes with it; hanging from one, its line goes
    /// with it.
    func thingsCarried(_ offsets: [Int: V2]) {
        guard inHabitat, !offsets.isEmpty else { return }
        for id in offsets.keys { stirring[id] = (t + 0.7, 1) }
        if mode == .attached, !isHeld {
            if riding == nil, let on = underfoot, offsets[on] != nil {
                // Picked up with it: it holds on for dear life.
                riding = on
                queued = nil
                walkThen = nil
                walkGoal = nil
                routeHop = nil
                pendingJump = nil
                beginActivity(.brace, dur: 60)
                startled.velocity = 5
                setEmote(.surprise, 0.6)
                if let tank, let it = tank.item(id: on) { knowledge?.unsettle(it, by: 0.3) }
            }
            if let on = riding, let d = offsets[on] { rideShift = d }
        } else if mode == .dangling, webActive {
            // A line hung from it goes where it goes.
            for (id, d) in offsets {
                guard let it = tank?.item(id: id) else { continue }
                let was = carriedAt[id] ?? .zero
                if it.rect.offsetBy(dx: was.x, dy: was.y).insetBy(dx: -map.standoff * 1.5, dy: -map.standoff * 1.5).contains(webAnchor.point) {
                    webAnchor += d - was
                    break
                }
            }
        }
        for (id, d) in offsets { carriedAt[id] = d }
    }

    /// Decorating: what was being carried is put down just where it was —
    /// the surfaces are as they were, and so is it.
    func thingsPutDown() {
        carriedAt = [:]
        guard riding != nil else { return }
        riding = nil
        rideShift = .zero
        if mode == .attached, activity == .brace { beginActivity(.look, dur: randRange(0.8, 1.4)) }
    }

    /// Back on its feet after the surfaces were laid out again: on the very
    /// thing it was standing on if that was moved (carried, it rode it
    /// already; moved otherwise, it goes with it), else wherever is nearest
    /// where it stood — a step or a little hop out of the way if something
    /// has come down where it was — or it drops.
    private func retakeFooting(_ change: HabitatChange) {
        guard mode == .attached else { return }
        let sc = config.scale
        var on = riding
        if let u = riding ?? underfoot, let m = change.moved.first(where: { $0.now.id == u }) {
            // However far it has come that it didn't ride: moved in one go
            // (in the overview, by the arrow keys), or the last of a carry
            // (pulled into place, settling onto what is under it) — it goes
            // with it just the same.
            let rest = V2(m.now.x - m.was.x, m.now.y - m.was.y) - (riding != nil ? rideShift : .zero)
            if rest.length > 0.5 { teleportQuietly(to: pos + rest) }
            on = u
        }
        if let id = on, let s = HabitatItem.spot(on: map, near: anchorPos, within: 30 * sc, ownedBy: id) {
            takeHold(s.anchor)
            if riding != nil, activity == .brace { beginActivity(.look, dur: randRange(0.8, 1.4)) }
            return
        }
        guard let spot = map.nearestSpot(to: anchorPos, within: 90 * sc) else {
            detachAndFall()
            return
        }
        if spot.point.distance(to: anchorPos) < 14 * sc {
            takeHold(spot.anchor)
        } else {
            hopClear(to: spot.point)
        }
    }

    /// Takes hold of `a`, where it stands, keeping on the way it was going
    /// across the tank, and gliding the little way onto it.
    private func takeHold(_ a: Anchor) {
        let wasAlong = surfaceNormal.rotated(by: -.pi / 2)
        if let s = map.seg(a), s.dir.dot(wasAlong) < 0 {
            walkDir = -walkDir
            facing = -facing
            pendingDir = -pendingDir
        }
        anchor = a
        lastLoopRect = nil
        stuckFor = 0
        anchorValid = true
        anchorGlide = 6
        walkGoal = nil
        routeHop = nil
    }

    /// A little hop onto `p`: out from under something put down on it, or
    /// off what went from under it.
    private func hopClear(to p: V2) {
        let g = -gravity.y
        let apex = max(p.y, pos.y) + 24 * config.scale
        let vy = (2 * g * max(apex - pos.y, 4)).squareRoot()
        let rise = vy / g
        let fall = (2 * max(apex - p.y, 1) / g).squareRoot()
        mode = .airborne
        air = .jump
        airTime = 0
        vel = V2((p.x - pos.x) / (rise + fall), vy)
        noAttachFor = rise * 0.6
        launchLoop = ""
        anchorValid = false
        if let spot = map.nearestSpot(to: p, within: 30 * config.scale) { landing = (spot.point, spot.seg.angle, spot.seg.dir) }
        legMode = .free
        activity = .idle
        startled.velocity = 6
        setEmote(.surprise, 0.6)
    }

    /// What has changed round it, taken in: things put in are seen landing,
    /// things moved are seen going (and, known or not, looked at again),
    /// something it was looking into taken away is looked round for — and
    /// a lot changed at once has it out exploring.
    private func takeIn(_ change: HabitatChange) {
        guard let know = knowledge else { return }
        let sc = config.scale
        changesAt = changesAt.filter { t - $0 < 90 } + Array(repeating: t, count: min(change.count, 6))
        if change.overhaul || changesAt.count >= 5 {
            exploreUntil = t + lerp(90, 240, personality.curiosity)
            inquiryRestUntil = min(inquiryRestUntil, t + 2)
            changesAt = []
        }
        for it in change.added { stirring[it.id] = (t + 1.6, 1) }
        // Something put down near it: whatever it was idly off to can wait.
        if let e = errand, e.kind.yields, change.added.contains(where: { worthKnowing($0) && distance(to: $0) < 300 * sc }) {
            endErrand(how: 0)
            if mode == .attached, [.walk, .sneak, .scurry].contains(activity) { activityDur = min(activityDur, activityTime) }
        }
        for m in change.moved {
            stirring[m.now.id] = (t + 1.2, 0.8)
            guard distance(to: m.now) < 420 * sc || distance(to: m.was) < 420 * sc else { continue }
            switch know.stage(of: m.now.uid) {
            case .unknown:
                break
            case .familiar:
                // Something it knows, somewhere else: it sees it go.
                know.unsettle(m.now, by: 0.12)
                glance(at: m.now)
            case .noticed, .investigating:
                know.unsettle(m.now, by: 0.35)
                if inquiry?.uid == m.now.uid { thingStirred(m.now) } else { glance(at: m.now) }
            }
        }
        if let q = inquiry, change.removed.contains(where: { $0.uid == q.uid }) {
            // Gone: a look round for it.
            endInquiry()
            if mode == .attached, [.idle, .look, .walk, .sneak, .feel, .peer].contains(activity) { beginActivity(.look, dur: randRange(0.8, 1.4)) }
        }
        // Something big put down right by it is noticed at once.
        for it in change.added where worthKnowing(it) && distance(to: it) < 140 * sc && sqrt(it.w * it.h) / (60 * sc) > Spider.bigThing && alertness > 0.15 {
            noticed(it)
        }
    }

    /// A look at something that moved, if it is free to.
    private func glance(at it: HabitatItem) {
        guard mode == .attached, alertness > 0.3, riding == nil else { return }
        look(at: focusPoint(it), for: randRange(0.9, 1.6))
        if inquiry == nil, distractable, [.idle, .look, .fidget, .groom, .scratch, .glance, .rest].contains(activity) {
            beginActivity(.look, dur: eyeOnUntil - t)
        }
    }

    /// Every frame in the tank: what it notices, and getting used to what it
    /// has.
    private func senseTank(dt: CGFloat) {
        guard let tank, let know = knowledge else { return }
        guard inHabitat else {
            if inquiry != nil { endInquiry() }
            if errand != nil { endErrand(how: 0) }
            eyeOn = nil
            riding = nil
            rideShift = .zero
            return
        }
        if mode != .attached { underfoot = nil }
        for (k, s) in stirring where t > s.until { stirring[k] = nil }
        if eyeOn != nil, t > eyeOnUntil { eyeOn = nil }
        if riding != nil, mode != .attached { riding = nil; rideShift = .zero }
        let sc = config.scale

        // Looking into something: watching it, being near it, on it — it
        // gets to know it.
        if let q = inquiry, let it = tank.item(uid: q.uid) {
            let near = distance(to: it) < 420 * sc
            var rate: CGFloat
            switch q.stage {
            case .orient, .watch: rate = near ? 0.022 : 0
            case .approach, .probe: rate = 0.012
            case .linger: rate = 0.03
            case .retreat: rate = 0
            }
            if underfoot == it.id { rate += 0.03 }
            if rate > 0, know.expose(it, by: rate * dt) { cameToKnow(it) }
        }
        livePlaces(dt: dt)

        senseIn -= dt
        guard senseIn <= 0, !config.paused else { return }
        let tick: CGFloat = 0.25
        senseIn = tick
        know.calm(for: tick)
        placesTick(tick)
        let alert = alertness
        let sight = (alert < 0.2 ? 110 : 520) * sc * (exploring ? 1.25 : 1)
        let P = personality
        for it in tank.items where worthKnowing(it) {
            switch know.stage(of: it.uid) {
            case .unknown:
                let d = distance(to: it)
                guard d < sight else { continue }
                let rate = HabitatKnowledge.noticeRate(distance: d, sight: sight, size: sqrt(it.w * it.h) / (60 * sc), inView: canSee(it),
                                                       motion: stirring[it.id]?.amount ?? 0, alert: alert, curiosity: P.curiosity,
                                                       kind: know.kindFamiliarity(it.kind)) * (exploring ? 1.6 : 1)
                if chance(rate * tick) {
                    debugLastNotice = String(format: "%@ at %.0f, %.2f a second", it.kind.rawValue, Double(d), Double(rate))
                    noticed(it)
                }
            case .noticed, .investigating:
                // Living alongside it with nothing going wrong, it grows used
                // to it all the same.
                if inquiry?.uid != it.uid, distance(to: it) < 260 * sc, alert > 0.05,
                   know.expose(it, by: tick / 200) {
                    cameToKnow(it)
                }
            case .familiar:
                break
            }
        }
    }

    /// Whether it could see `it` from where it is: nothing solid between.
    private func canSee(_ it: HabitatItem) -> Bool {
        let sc = config.scale
        let eye = pos + surfaceNormal * 8 * sc
        let r = it.rect
        let aim = V2(clamp(eye.x, r.minX + 2, r.maxX - 2), clamp(eye.y, r.minY + 2, r.maxY - 2))
        let ray = aim - eye, len = ray.length
        guard len > 1 else { return true }
        let box = CGRect(x: min(eye.x, aim.x) - 1, y: min(eye.y, aim.y) - 1, width: abs(ray.x) + 2, height: abs(ray.y) + 2)
        var hits: [CGFloat] = []
        for l in map.loops where l.rect.isNull || l.rect.insetBy(dx: -4, dy: -4).intersects(box) {
            for (i, s) in l.segs.enumerated() {
                if i < l.owners.count, l.owners[i] == it.id { continue }
                guard max(s.a.x, s.b.x) >= box.minX, min(s.a.x, s.b.x) <= box.maxX,
                      max(s.a.y, s.b.y) >= box.minY, min(s.a.y, s.b.y) <= box.maxY else { continue }
                let sd = s.b - s.a
                let den = ray.cross(sd)
                guard abs(den) > 1e-9 else { continue }
                let w = s.a - eye
                let u = w.cross(sd) / den, v = w.cross(ray) / den
                if u >= 0, u <= 1, v >= 0, v <= 1 { hits.append(u * len) }
            }
        }
        // Through something solid (in one side and out the other) is out of
        // sight; the edge of what it stands on, or of what it is looking
        // at, isn't.
        let inner = hits.filter { $0 > 10 * sc }.sorted()
        var k = 0
        while k + 1 < inner.count {
            if inner[k + 1] - inner[k] >= 8 { return false }
            k += 2
        }
        return true
    }

    /// It has seen `it`: it stops and looks — or, something big dropped
    /// right by it, it jumps and backs off to watch.
    private func noticed(_ it: HabitatItem) {
        guard let tank, let know = knowledge, know.stage(of: it.uid) == .unknown else { return }
        let sc = config.scale
        let P = personality
        let q = tank.qualities(of: it)
        let d = distance(to: it)
        let big = sqrt(it.w * it.h) / (60 * sc)
        let moving = stirring[it.id]?.amount ?? 0
        // How it feels about it to begin with: the bigger, the more it moves
        // or hangs over it or glows, the warier — the timid all the more.
        let unease = clamp((0.12 + 0.18 * clamp(big - 1, 0, 2.5) + 0.2 * q[.moving] + 0.15 * q[.hanging] + 0.1 * q[.glowing] + 0.25 * moving)
                           * lerp(1.7, 0.35, P.bravery), 0, 1)
        know.notice(it, unease: unease)
        guard mode == .attached, !isHeld, riding == nil, activity != .sleep, !dormant else { return }
        // (Big: twice its own size across, or more — a boulder, a stump, not
        // a toadstool.)
        if moving > 0.3, big > Spider.bigThing, d < 60 * sc * min(big, 3), chance(lerp(0.95, 0.25, P.bravery)) {
            frightenedBy(it)
            return
        }
        guard inquiry == nil, distractable || activity == .rest else { return }
        let f = focusPoint(it)
        look(at: f, for: randRange(1.2, 2.0) * lerp(0.8, 1.3, P.curiosity))
        if [.walk, .sneak, .idle, .look, .fidget, .groom, .scratch, .glance, .peer].contains(activity) {
            queued = nil
            walkThen = nil
            beginActivity(.look, dur: eyeOnUntil - t)
        }
        if chance(lerp(0.2, 0.6, P.curiosity)) { setEmote(.question, 0.9) }
        freshlyNoticed = it.uid
        decisionIn = min(decisionIn, eyeOnUntil - t + 0.3)
    }

    /// Something big came down right by it: a start, and — unless it is a
    /// bold one — back off, to watch it from a safe way off.
    private func frightenedBy(_ it: HabitatItem) {
        wake()
        queued = nil
        walkThen = nil
        pendingJump = nil
        startled.velocity = 9 * lerp(1.3, 0.7, personality.bravery)
        setEmote(.exclaim, 0.7)
        remember(.startled, 0.3)
        knowledge?.unsettle(it, by: 0.3)
        let from = focusPoint(it)
        noteFright(from: from)
        if errand != nil { endErrand(how: 0) }
        if inquiry != nil { endInquiry() }
        beginInquiry(it, retreating: personality.bravery < 0.65)
        if surfaceNormal.y > 0.85 {
            startleHop(awayFrom: from)
        } else {
            beginActivity(.startle, dur: 0.55)
        }
        look(at: from, for: 3)
        decisionIn = 0.3
    }

    /// Now familiar: nothing to make of it any more. It finishes up
    /// where it is, without fuss.
    private func cameToKnow(_ it: HabitatItem) {
        memory?.meet("thing.\(it.kind.rawValue)")
        guard var q = inquiry, q.uid == it.uid, q.stage != .linger, !q.doing else { return }
        q.stage = .linger
        q.stageSince = t
        q.doing = false
        q.lingerFor = randRange(1.5, 4)
        inquiry = q
    }

    /// Picks something it has noticed, and doesn't know yet, to look into —
    /// if it feels like it: likelier the more curious it is, the more there
    /// is to it and the nearer; at once for what it has only just noticed;
    /// all the more exploring. True if it did.
    private func startInquiry() -> Bool {
        guard inquiry == nil, let tank, let know = knowledge, inHabitat, mode == .attached, riding == nil else { return false }
        let fresh = freshlyNoticed
        freshlyNoticed = nil
        guard t >= inquiryRestUntil || (fresh != nil && exploring) else { return false }
        let sc = config.scale
        let P = personality
        var best: (score: CGFloat, it: HabitatItem)?
        for it in tank.items where worthKnowing(it) {
            guard let a = know.acquaintance(it.uid), a.stage == .noticed else { continue }
            let d = distance(to: it)
            guard d < 900 * sc else { continue }
            let score = (0.5 + tank.qualities(of: it)[.interesting]) * (1 - a.unease * 0.5) / (1 + d / (300 * sc)) * (it.uid == fresh ? 2 : 1)
            if score > best?.score ?? 0 { best = (score, it) }
        }
        guard let b = best else { return false }
        let want = lerp(0.12, 0.8, P.curiosity) * (exploring ? 1.5 : 1) * (b.it.uid == fresh ? 1.6 : 1) * lerp(1, 0.5, drowsy)
        guard chance(min(0.95, want)) else {
            inquiryRestUntil = t + randRange(4, 12)
            return false
        }
        beginInquiry(b.it)
        return true
    }

    private func beginInquiry(_ it: HabitatItem, retreating: Bool = false) {
        guard let know = knowledge else { return }
        if errand != nil { endErrand(how: 0) }
        let P = personality
        let sc = config.scale
        let unease = know.acquaintance(it.uid)?.unease ?? 0.3
        var q = Inquiry(uid: it.uid, since: t, stageSince: t, todo: planProbes(it),
                        comfort: (lerp(70, 26, P.bravery) + unease * 140) * sc + max(it.w, it.h) * 0.2)
        q.stage = retreating ? .retreat : .orient
        q.side = pos.x < it.rect.midX ? -1 : 1
        q.lastPos = pos
        inquiry = q
        know.investigating(it, true)
        queued = nil
        walkThen = nil
        decisionIn = min(decisionIn, 0.2)
    }

    /// Done with it for now — finished, given up, or called away.
    private func endInquiry() {
        if let q = inquiry, let it = tank?.item(uid: q.uid) { knowledge?.investigating(it, false) }
        inquiry = nil
        walkGoal = nil
        routeHop = nil
        feelAt = nil
        eyeOnUntil = min(eyeOnUntil, t + 0.8)
        inquiryRestUntil = t + (exploring ? randRange(3, 8) : randRange(12, 30))
    }

    /// What there is to find out about `it`, for its shape and for who this
    /// spider is: first a feel of it (or a close look at it), then some of
    /// the rest — round the other side, under it, into it, at its water,
    /// partway up it, up on top, a leap straight on — more of them for a
    /// curious one, the climbing likelier for a bold one; in a sensible
    /// order.
    private func planProbes(_ it: HabitatItem) -> [Probe] {
        guard let tank else { return [] }
        let pts = it.interactionPoints(on: map)
        let q = tank.qualities(of: it)
        let P = personality
        func has(_ k: InteractionPoint.Kind, _ n: Int = 1) -> Bool { pts.filter { $0.kind == k && $0.stand != nil }.count >= n }
        let first: [Probe] = [has(.touch) ? .feel : .peer]
        var pick: [(Probe, CGFloat)] = []
        if has(.drinkEdge) { pick.append((.water, 1.3)) }
        if has(.entrance) { pick.append((.inside, 1.2)) }
        if has(.beneath) { pick.append((.beneath, 1.1)) }
        if has(.touch, 2) || has(.inspect, 2) { pick.append((.otherSide, 0.8)) }
        let from = pts.first { $0.kind == .touch && $0.stand != nil }?.stand ?? pts.first { $0.kind == .inspect && $0.stand != nil }?.stand
        let walkOn = q[.climbable] > 0.4 && walkable(onto: it, from: from)
        if walkOn, has(.side) { pick.append((.partway, lerp(0.5, 1.3, P.bravery))) }
        if has(.top) {
            if walkOn { pick.append((.top, lerp(0.35, 1.5, P.bravery) * (0.4 + q[.perchable]))) }
            if P.bravery > 0.45, q[.climbable] > 0.4 { pick.append((.leapOn, lerp(0, 1.6, (P.bravery - 0.45) / 0.55) * (0.4 + q[.perchable]))) }
        }
        let n = max(1, Int((lerp(1.2, 4.4, P.curiosity) + (exploring ? 1 : 0) + randRange(-0.6, 0.6)).rounded()))
        var chosen: [Probe] = []
        while chosen.count < n - 1, !pick.isEmpty {
            let total = pick.reduce(0) { $0 + $1.1 }
            var r = randRange(0, total)
            var k = 0
            while k < pick.count - 1, r > pick[k].1 { r -= pick[k].1; k += 1 }
            chosen.append(pick.remove(at: k).0)
            // (Up on top one way or the other: not both.)
            if chosen.last == .top || chosen.last == .leapOn { pick.removeAll { $0.0 == .top || $0.0 == .leapOn } }
        }
        let order: [Probe] = [.feel, .peer, .water, .beneath, .inside, .otherSide, .partway, .top, .leapOn]
        return first + chosen.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
    }

    /// Whether it could walk onto `it` from `from`: it is part of the same
    /// surface (a stone the ground runs over), or the way there goes over
    /// onto it (a stem off the ground).
    private func walkable(onto it: HabitatItem, from: Anchor?) -> Bool {
        guard let from else { return false }
        let own = map.loops.filter { $0.owners.contains(it.id) }.map(\.id)
        return own.contains(from.loopID) || own.contains { firstHops(from: from.loopID, to: $0) != nil }
    }

    /// Where to be for a go at `probe`, on the side it is working from.
    private func placeFor(_ probe: Probe, _ it: HabitatItem, side: CGFloat) -> InteractionPoint? {
        let pts = it.interactionPoints(on: map).filter { $0.stand != nil }
        func sideOf(_ p: InteractionPoint) -> CGFloat { (p.standPoint ?? p.point).x < it.rect.midX ? -1 : 1 }
        func pick(_ k: InteractionPoint.Kind, side s: CGFloat? = nil) -> InteractionPoint? {
            let c = pts.filter { $0.kind == k && (s == nil || sideOf($0) == s) }
            return c.min { ($0.standPoint ?? $0.point).distance(to: pos) < ($1.standPoint ?? $1.point).distance(to: pos) }
        }
        switch probe {
        case .feel: return pick(.touch, side: side) ?? pick(.touch)
        case .peer: return pick(.touch, side: side) ?? pick(.inspect, side: side) ?? pick(.inspect)
        case .water: return pick(.drinkEdge)
        case .beneath: return pick(.beneath)
        case .inside: return pick(.entrance)
        case .otherSide: return pick(.touch, side: -side) ?? pick(.inspect, side: -side)
        case .partway:
            // A way up its side — not all the way.
            let want = it.rect.minY + it.rect.height * 0.4
            return pts.filter { $0.kind == .side }.min { abs($0.point.y - want) < abs($1.point.y - want) }
        case .top, .leapOn: return pick(.top) ?? pick(.perch)
        }
    }

    /// How far it has to go to `a`: along the surface if it is on the same
    /// one, else as the crow flies.
    private func wayTo(_ p: InteractionPoint) -> CGFloat {
        guard let a = p.stand else { return .greatestFiniteMagnitude }
        if a.loopID == anchor.loopID, let w = loopWay(to: a) { return w.dist }
        return (p.standPoint ?? p.point).distance(to: pos)
    }

    /// One decision's worth of looking into something. False once there is
    /// nothing more to it, for now.
    private func pursueInquiry() -> Bool {
        guard let tank, let know = knowledge, var q = inquiry, let it = tank.item(uid: q.uid) else {
            endInquiry()
            return false
        }
        guard mode == .attached else { return true }
        let P = personality
        let sc = config.scale
        decisionIn = randRange(0.25, 0.55)
        // (Down from a hop backwards — a start — it still faces the way it
        // did: which way it goes next is reckoned from that.)
        if walkDir != facing, speed < 1, activity != .turn { walkDir = facing }
        let a = know.acquaintance(q.uid)
        let unease = a?.unease ?? 0
        let d = distance(to: it)
        let focus = focusPoint(it)
        // At it too long: enough for now.
        if t - q.since > lerp(70, 160, P.curiosity) {
            endInquiry()
            return false
        }
        // It knows it now: it only finishes up.
        if a?.stage == .familiar, q.stage != .linger, !q.doing {
            q.stage = .linger
            q.stageSince = t
            q.lingerFor = randRange(1.5, 4)
        }
        func face(_ p: V2, then next: Activity, for dur: CGFloat) {
            if let dir = alongEdge(to: p), dir != walkDir, abs((p - pos).dot(map.seg(anchor)?.dir ?? V2(1, 0))) > 6 * sc {
                turnTo(dir, then: next, for: dur)
            } else {
                beginActivity(next, dur: dur)
            }
        }
        func toStage(_ s: InquiryStage) {
            q.stage = s
            q.stageSince = t
            q.doing = false
            q.step = 0
        }

        switch q.stage {
        case .orient:
            // Stop, and face it.
            look(at: focus, for: 2)
            face(focus, then: .look, for: randRange(0.8, 1.4))
            toStage(.watch)
            q.watchFor = lerp(3.5, 1.0, P.bravery) * lerp(1.3, 0.8, P.curiosity) * (0.6 + unease)

        case .watch:
            look(at: focus, for: 2)
            if d < q.comfort * 0.6, unease > 0.45 {
                toStage(.retreat)
                decisionIn = 0
                break
            }
            if t - q.stageSince < q.watchFor {
                face(focus, then: .look, for: min(q.watchFor - (t - q.stageSince) + 0.2, randRange(1.0, 2.0)))
                break
            }
            // Seen enough from here: closer — or not, just now.
            q.watches += 1
            if chance(lerp(0.35, 0.95, (P.curiosity + P.bravery) / 2) * (1 - unease * 0.5)) {
                toStage(.approach)
                decisionIn = 0.05
            } else if q.watches >= 3 {
                endInquiry()
                return false
            } else {
                q.stageSince = t
                q.watchFor = randRange(1.5, 3)
                face(focus, then: .look, for: randRange(1.0, 1.8))
            }

        case .approach:
            if q.pause {
                // A leg of the way in: a stop to watch it before the next.
                q.pause = false
                toStage(.watch)
                q.watchFor = randRange(0.8, 1.8) * (0.6 + unease)
                q.comfort *= lerp(0.55, 0.85, unease)
                face(focus, then: .look, for: q.watchFor)
                break
            }
            guard let probe = q.todo.first else {
                toStage(.linger)
                q.lingerFor = lerp(3, 9, P.curiosity) * randRange(0.8, 1.2)
                decisionIn = 0
                break
            }
            // Climbing it is only for when it is easy about it.
            if [.partway, .top, .leapOn].contains(probe), unease > lerp(0.35, 0.8, P.bravery) {
                q.todo.removeFirst()
                decisionIn = 0.05
                break
            }
            guard let spot = placeFor(probe, it, side: q.side), let stand = spot.stand else {
                q.todo.removeFirst()
                decisionIn = 0.05
                break
            }
            q.at = spot
            if probe == .leapOn {
                // From here, if it can make it; else first to somewhere it can.
                if let p = spot.standPoint, p.distance(to: pos) < 260 * sc, ballistic(from: pos, to: p) != nil {
                    look(at: p, for: 1.5)
                    startJump(to: p)
                    toStage(.probe)
                    q.doing = true
                    break
                }
                if q.stalls > 0 || d < 30 * sc {
                    // No leap to be had: up the ordinary way, if there is one.
                    q.todo[0] = .top
                    q.stalls = 0
                    break
                }
                q.stalls += 1
                if let near = placeFor(.peer, it, side: q.side), let s = near.stand, headFor(s, style: .walk, within: 8 * sc) == .going {
                    break
                }
                q.todo[0] = .top
                break
            }
            let togo = wayTo(spot)
            let style: Activity = unease > 0.45 || P.bravery < 0.35 ? .sneak : .walk
            // A timid one comes in by stages; a bold one straight up to it.
            let stepLen = lerp(50, 400, P.bravery) * (1 - unease * 0.6) * sc
            let staged = togo > stepLen + 30 * sc && (unease > 0.3 || P.bravery < 0.5) && stand.loopID == anchor.loopID
            let within = staged ? togo - stepLen : 4 * sc
            // Getting nowhere: the next go instead.
            if q.went { q.stalls = pos.distance(to: q.lastPos) < 4 * sc ? q.stalls + 1 : 0 }
            q.went = false
            q.lastPos = pos
            if q.stalls > 3 {
                q.todo.removeFirst()
                q.stalls = 0
                decisionIn = 0.05
                break
            }
            if eyeOnPlace(probe) { look(at: focus, for: 2) }
            switch headFor(stand, style: style, within: within) {
            case .going:
                q.went = true
                q.pause = staged
            case .there:
                toStage(.probe)
                decisionIn = 0
            case .noWay:
                // No walking there: a leap, if it can make one; else the next go.
                if let p = spot.standPoint, P.bravery > 0.3, p.distance(to: pos) < 300 * sc, ballistic(from: pos, to: p) != nil {
                    startJump(to: p)
                } else {
                    q.todo.removeFirst()
                    decisionIn = 0.05
                }
            }

        case .retreat:
            if !q.doing {
                // Back off from it: a quick scuttle the other way (eyes on
                // where it is going; it looks back once it is clear).
                q.doing = true
                q.retreats += 1
                q.comfort *= 1.25
                eyeOn = nil
                // Far enough to be easy about it again, and a little more.
                let away: CGFloat = -(alongEdge(to: focus) ?? walkDir)
                let far = max(q.comfort - d, 30 * sc) * randRange(0.8, 1.2)
                turnTo(away, then: .scurry, for: clamp(far / max(config.walkSpeed * 1.9 * 0.85, 1) + 0.3, 0.6, 2.0))
                walkThen = nil
            } else {
                // Far enough: round, to watch it — unless it has had enough of it.
                if q.retreats > Int(lerp(1, 4, P.curiosity).rounded()) {
                    endInquiry()
                    beginActivity(.look, dur: randRange(1.0, 2.0))
                    return false
                }
                look(at: focus, for: 2)
                toStage(.watch)
                q.watchFor = lerp(3, 1, P.bravery) * (0.6 + unease)
                face(focus, then: .look, for: q.watchFor)
            }

        case .probe:
            guard let probe = q.todo.first, let spot = q.at else {
                toStage(.approach)
                decisionIn = 0.05
                break
            }
            if !q.doing {
                q.doing = true
                q.step = 0
                // (Round the other side, it works from there on.)
                if probe == .otherSide { q.side = -q.side }
                haveAGo(probe, at: spot, it)
            } else {
                var more = false
                if probe == .partway, q.step == 0 {
                    // Partway up: and back down again.
                    q.step = 1
                    if let back = placeFor(.feel, it, side: q.side) ?? placeFor(.peer, it, side: q.side), let s = back.stand {
                        more = headFor(s, style: .walk, within: 6 * sc) == .going
                    }
                } else if probe == .water, q.step == 0, feelAt != nil {
                    // A good look at it, then a front leg to the water.
                    q.step = 1
                    beginActivity(.feel, dur: randRange(1.2, 1.8))
                    more = true
                }
                if !more { finishGo(probe, it, &q) }
            }

        case .linger:
            if !q.doing {
                q.doing = true
                q.stageSince = t
                // Settled near it — or on it — a while, watching.
                let on = underfoot == it.id
                let settle: Activity = chance(0.3 + P.laziness * 0.4) ? .rest : .look
                beginActivity(settle, dur: q.lingerFor)
                if !on { look(at: focus, for: q.lingerFor) }
                decisionIn = q.lingerFor
            } else if t - q.stageSince < q.lingerFor {
                beginActivity(.look, dur: max(0.5, q.lingerFor - (t - q.stageSince)))
            } else {
                endInquiry()
                return false
            }
        }
        if inquiry != nil { inquiry = q }
        return true
    }

    /// Whether, going to have this go, its eyes stay on the thing (not up
    /// on it, where it looks about instead).
    private func eyeOnPlace(_ probe: Probe) -> Bool { ![.partway, .top, .leapOn].contains(probe) }

    /// Sets about a go at it, standing where it should.
    private func haveAGo(_ probe: Probe, at spot: InteractionPoint, _ it: HabitatItem) {
        let sc = config.scale
        let face = spot.facing
        feelAt = nil
        switch probe {
        case .feel:
            // Front legs out to it, feeling it.
            feelAt = spot.point
            feelNormal = spot.normal
            look(at: spot.point, for: 3)
            turnTo(face, then: .feel, for: randRange(1.4, 2.3))
        case .peer:
            look(at: focusPoint(it), for: 2.5)
            turnTo(face, then: .peer, for: randRange(1.2, 1.8))
        case .water:
            // A good look at it, and a front leg to the water.
            let w = it.interactionPoints(on: map).first { $0.kind == .waterSurface }?.point ?? spot.point
            let reachX = pos.x + (w.x >= pos.x ? 1 : -1) * 20 * sc
            feelAt = V2(w.x >= pos.x ? min(reachX, w.x) : max(reachX, w.x), w.y)
            feelNormal = V2(0, 1)
            look(at: w, for: 4)
            turnTo(walkDirToward(w), then: .peer, for: randRange(1.0, 1.5))
        case .beneath:
            // Under it: a look up at the underside of it.
            look(at: spot.point, for: 3)
            beginActivity(.look, dur: randRange(1.6, 2.6))
        case .inside:
            let inner = it.interactionPoints(on: map).first { $0.kind == .interior }?.point ?? spot.point
            look(at: inner, for: 3)
            turnTo(walkDirToward(inner), then: .peer, for: randRange(1.4, 2.2))
        case .otherSide:
            if spot.kind == .touch {
                feelAt = spot.point
                feelNormal = spot.normal
                look(at: spot.point, for: 3)
                turnTo(face, then: .feel, for: randRange(1.2, 2.0))
            } else {
                look(at: focusPoint(it), for: 2)
                turnTo(face, then: .look, for: randRange(1.0, 1.8))
            }
        case .partway:
            // Holding on up its side, a look about.
            eyeOn = nil
            beginActivity(.look, dur: randRange(1.0, 2.0))
        case .top:
            // On top of it: a good look round from up there.
            eyeOn = nil
            beginActivity(.look, dur: randRange(1.6, 3.2))
            if chance(0.35) { queue(.rest, randRange(2, 5)) }
        case .leapOn:
            // (Under way: see `finishGo` once it is down.)
            break
        }
    }

    /// Which way along its edge `p` is (+1 / -1), or the way it faces now.
    private func walkDirToward(_ p: V2) -> CGFloat { alongEdge(to: p) ?? walkDir }

    /// A go at it over: it knows it that much better.
    private func finishGo(_ probe: Probe, _ it: HabitatItem, _ q: inout Inquiry) {
        let P = personality
        feelAt = nil
        let gain: CGFloat
        switch probe {
        case .feel: gain = 0.16
        case .peer: gain = 0.08
        case .water, .beneath, .inside: gain = 0.12
        case .otherSide: gain = 0.12
        case .partway: gain = 0.15
        case .top: gain = underfoot == it.id ? 0.2 : 0.06
        case .leapOn:
            gain = underfoot == it.id ? 0.22 : 0.05
            if underfoot == it.id {
                // Down on it: a look round from up there.
                eyeOn = nil
                beginActivity(.look, dur: randRange(1.4, 2.6))
            }
        }
        q.todo.removeFirst()
        q.done.append(probe)
        q.doing = false
        q.step = 0
        q.stageSince = t
        knowledge?.expose(it, by: gain * lerp(0.8, 1.2, P.bravery))
        if knowledge?.isFamiliar(it.uid) == true {
            q.stage = .linger
            q.lingerFor = randRange(1.5, 4)
            decisionIn = 0.1
            return
        }
        q.stage = q.todo.isEmpty ? .linger : .approach
        if q.stage == .linger { q.lingerFor = lerp(3, 9, P.curiosity) * randRange(0.8, 1.2) }
        // A wary one steps back to take it in again between goes.
        if q.stage == .approach, (knowledge?.acquaintance(q.uid)?.unease ?? 0) > 0.4, chance(0.4) {
            q.stage = .retreat
        }
        decisionIn = 0.1
    }

    /// Something it is looking into moved: a wary one backs off from it; a
    /// bold one stops to watch it.
    private func thingStirred(_ it: HabitatItem) {
        guard var q = inquiry, q.uid == it.uid, mode == .attached else { return }
        let unease = knowledge?.acquaintance(it.uid)?.unease ?? 0
        walkGoal = nil
        routeHop = nil
        feelAt = nil
        q.doing = false
        q.step = 0
        q.stageSince = t
        if unease > 0.35 || personality.bravery < 0.45 {
            q.stage = .retreat
            startled.velocity = 5
            setEmote(.surprise, 0.5)
        } else {
            q.stage = .watch
            q.watchFor = randRange(1, 2)
            beginActivity(.look, dur: q.watchFor)
        }
        look(at: focusPoint(it), for: 2)
        inquiry = q
        decisionIn = 0.05
    }

    /// Exploring after a rearrangement: over toward the nearest thing it has
    /// not got the measure of yet — noticed or not — or, with nothing like
    /// that about, off somewhere.
    private func explore() {
        guard let tank, let know = knowledge else { return }
        let sc = config.scale
        let new = tank.items.filter { worthKnowing($0) && !know.isFamiliar($0.uid) && distance(to: $0) < 1500 * sc }
        if let it = new.min(by: { distance(to: $0) < distance(to: $1) }),
           let spot = it.interactionPoints(on: map).first(where: { $0.kind == .inspect && $0.stand != nil }), let stand = spot.stand {
            switch headFor(stand, style: .walk, within: 24 * sc) {
            case .going:
                return
            case .there:
                look(at: focusPoint(it), for: 1.6)
                beginActivity(.look, dur: randRange(0.8, 1.6))
                return
            case .noWay:
                if let p = spot.standPoint, ballistic(from: pos, to: p) != nil {
                    startJump(to: p)
                    return
                }
            }
        }
        if chance(0.4), let s = bestJumpSpot(from: pos, exclude: anchor.loopID) {
            startJump(to: s.point)
        } else {
            turnTo(chance(0.6) ? walkDir : -walkDir, then: .walk, for: randRange(2, 4.5))
        }
    }

    // Getting about by the surfaces themselves.

    private enum Headway { case there, going, noWay }
    /// How far the way `headFor` set off on goes, all told.
    private var headDist: CGFloat = 0

    /// Off toward `goal` over the surfaces themselves — along what it is on,
    /// and over onto whatever meets it on the way (a stem off the ground, the
    /// cap on the stem) — at `style`, to stop within `within` of it.
    private func headFor(_ goal: Anchor, style: Activity, within: CGFloat) -> Headway {
        // (In the tank, by its ways: see "Its ways about the tank".)
        if let way = navGo(to: goal, within: within, style: style) { return way }
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count, map.loop(goal.loopID) != nil else { return .noWay }
        walkGoal = nil
        routeHop = nil
        let pace = max(config.walkSpeed * (style == .scurry ? 1.9 : style == .sneak ? 0.42 : 1) * 0.7, 1)
        if goal.loopID == anchor.loopID {
            guard let way = loopWay(to: goal) else { return .noWay }
            guard way.dist > within else { return .there }
            headDist = way.dist
            walkGoal = (goal, within)
            lookAhead(way.dir)
            turnTo(way.dir, then: style, for: min((way.dist - within) / pace + 1, 14))
            return .going
        }
        // Onto another: to the nearest place where the way there leaves this
        // one, arriving there the way that goes over.
        guard let hops = firstHops(from: anchor.loopID, to: goal.loopID) else { return .noWay }
        var best: (d: CGFloat, dir: CGFloat, j: SurfaceJunction)?
        for j in hops {
            for dir in [CGFloat(1), -1] {
                guard let at = arrival(at: j, on: loop, dir: dir), var dd = loopDistance(loop, to: at, dir: dir) else { continue }
                // Over there it goes on the way it was going: onto the goal's
                // own surface, count how far on that is to it that way too
                // (the wrong way round the tank's rim is the long way).
                if j.to == goal.loopID, let next = map.loop(j.to), !next.segs.isEmpty {
                    let n = next.segs.count
                    let idx = dir > 0 ? j.toVertex % n : (j.toVertex - 1 + n) % n
                    let entry = Anchor(loopID: next.id, segIdx: idx, t: dir > 0 ? 0 : next.segs[idx].len)
                    guard let on = loopDistance(next, to: goal, dir: dir, from: entry) else { continue }
                    dd += on
                }
                dd *= routeBias(j)
                if dd < best?.d ?? .greatestFiniteMagnitude { best = (dd, dir, j) }
            }
        }
        guard let b = best else { return .noWay }
        headDist = b.d
        walkGoal = (goal, within)
        routeHop = b.j
        lookAhead(b.dir)
        turnTo(b.dir, then: style, for: min(b.d / pace + 1.5, 14))
        return .going
    }

    /// Setting off along its edge `dir`: whatever it had its eyes on back
    /// the other way, it lets go of — else, still turned to that, it comes
    /// round to it again the moment it moves, and walks off the wrong way.
    private func lookAhead(_ dir: CGFloat) {
        guard let e = eyeOn, t < eyeOnUntil, let s = map.seg(anchor) else { return }
        if (e - pos).dot(s.dir) * dir < 0 {
            eyeOn = nil
            eyeOnUntil = t
        }
    }

    /// How much shorter a way over it knows seems (and none of them quite
    /// exactly as long as it is: it doesn't always take the very best way).
    private func routeBias(_ j: SurfaceJunction) -> CGFloat {
        guard placesOn, let know = knowledge else { return 1 }
        var b = (1 - 0.35 * know.route(routeKey(j))) * randRange(0.9, 1.1)
        // In a gale, not by way of what sways in it if there is any other.
        if eco != nil, abs(weather.wind) > 0.55, let to = map.loop(j.to), let o = to.owners.first(where: { $0 != 0 }),
           tank?.item(id: o)?.kind.sways == true {
            b *= 1 + 2.5 * min(abs(weather.wind), 1.5)
        }
        return b
    }

    /// The first places it could go over from `from` on the fewest steps to
    /// `goal`: nil if there is no way at all.
    private func firstHops(from: String, to goal: String) -> [SurfaceJunction]? {
        let out = Dictionary(grouping: map.junctions, by: \.from)
        func steps(_ start: String) -> Int? {
            if start == goal { return 0 }
            var seen: Set<String> = [from, start]
            var frontier = [start]
            var depth = 0
            while !frontier.isEmpty, depth < 6 {
                depth += 1
                var next: [String] = []
                for l in frontier {
                    for j in out[l] ?? [] where !seen.contains(j.to) {
                        if j.to == goal { return depth }
                        seen.insert(j.to)
                        next.append(j.to)
                    }
                }
                frontier = next
            }
            return nil
        }
        var best: (depth: Int, hops: [SurfaceJunction])?
        var known: [String: Int?] = [:]
        for j in out[from] ?? [] {
            let s: Int?
            if let k = known[j.to] { s = k } else { s = steps(j.to); known[j.to] = s }
            guard let dd = s else { continue }
            if dd < best?.depth ?? .max { best = (dd, [j]) } else if dd == best?.depth { best!.hops.append(j) }
        }
        return best?.hops
    }

    /// Where on `loop` it arrives at junction `j` walking `dir` — if going
    /// over there that way is possible (it keeps the way it walks, so onto
    /// an open run it must go on along it, not off its end).
    private func arrival(at j: SurfaceJunction, on loop: SurfaceLoop, dir: CGFloat) -> Anchor? {
        let n = loop.segs.count
        guard n > 0, j.from == loop.id, let to = map.loop(j.to), !to.segs.isEmpty else { return nil }
        if !to.closed {
            if dir > 0, j.toVertex >= to.segs.count { return nil }
            if dir < 0, j.toVertex <= 0 { return nil }
        }
        let v = j.fromVertex
        if dir > 0 {
            guard loop.closed || v > 0 else { return nil }
            let i = (v - 1 + n) % n
            return Anchor(loopID: loop.id, segIdx: i, t: loop.segs[i].len)
        }
        guard loop.closed || v < n else { return nil }
        let i = v % n
        return Anchor(loopID: loop.id, segIdx: i, t: 0)
    }

    // MARK: Its ways about the tank
    //
    // (HabitatNav.swift.) In its tank it plans its way — walks, the ways
    // over from one surface to the next, leaps, doors — and follows it a
    // leg at a time: the cheapest way there, found afresh each time it
    // decides, so it keeps to the way it set off on unless something
    // changes. Without its ways (on the desktop, or for the moment it takes
    // to work them out after the tank is laid out again) it goes by the
    // surfaces alone, as `headFor` always has.

    /// The tank's ways, as worked out for the surfaces it has now.
    private var nav: TankNav?
    /// Working them out itself, for surfaces of this `generation`.
    private var navAsked: Int?
    /// The tank is working them out for it (see `tankRebuilt`), since then.
    private var navComing: CGFloat?
    /// The app has them worked out off the main thread (`workOutWays`); the
    /// tools — no run loop going — there and then, the first time they are
    /// wanted.
    static var waysOffMain = false
    private static let navQueue = DispatchQueue(label: "spider.ways", qos: .utility)

    /// A trip under way by the tank's ways.
    private struct NavTrip {
        var goal: Anchor
        var within: CGFloat
        var point: V2
        /// The ways it is planned on.
        var nav: ObjectIdentifier
        /// What it has found out on the way (see `NavLean.penalty`).
        var penalty: [Int32: Float] = [:]
        /// How it feels about leaping, this trip.
        var leapMood: Float
        /// The least it has had left to go, and when; and how often it has
        /// got no nearer for a good while.
        var bestLeft: Float = .infinity
        var bestAt: CGFloat
        var strikes = 0
        /// On the walk under way: the ways over it has still to take.
        var hops: [SurfaceJunction] = []
        var hopEdges: [Int32] = []
        /// A leap it set off to make — which, from where, and how many
        /// leaps it had launched before (see `launches`) — or a door.
        var leap: (edge: Int32, from: V2, launches: Int)?
        var door: (edge: Int32, from: V2)?
    }
    private var navTrip: NavTrip?
    /// A leg of it set going since it last decided.
    private var navLive = false
    /// How many leaps it has launched (a leap made, from one called off).
    private var launches = 0
    /// Prey it found it had no way to, let be until then.
    private var huntIgnore: [Int: CGFloat] = [:]
    private var reachCheckIn: CGFloat = 0
    /// The ways over it knows, as they bear on its plans (see `navLean`).
    private var navHopLean: (nav: ObjectIdentifier, at: CGFloat, hops: [Float])?

    /// The tank's ways for the surfaces it has now: nil on the desktop, or
    /// while they are being worked out.
    private func tankNav() -> TankNav? {
        guard inHabitat, !map.loops.isEmpty else { return nil }
        if let n = nav, n.fits(map, scale: config.scale) { return n }
        if !Spider.waysOffMain {
            let n = TankNav(map: map, habitat: tank, scale: config.scale)
            n.adopt(map)
            nav = n
            return n
        }
        // (The tank is working them out: unless that is taking far too long.)
        if let since = navComing, t - since < 4 { return nil }
        if navAsked != map.generation { workOutWays() }
        return nil
    }

    /// Works out the ways for the surfaces as they are, off the main thread.
    private func workOutWays() {
        let m = map, gen = m.generation, copy = m.habitatCopy(), h = tank, sc = config.scale
        navAsked = gen
        navComing = nil
        Spider.navQueue.async {
            let n = TankNav(map: copy, habitat: h, scale: sc)
            DispatchQueue.main.async { [weak self, weak m] in
                guard let self, let m, self.map === m, m.generation == gen else { return }
                n.adopt(m)
                self.nav = n
            }
        }
    }

    /// The tank has worked out its ways for the surfaces `m` has now.
    func waysWorkedOut(_ n: TankNav, for m: SurfaceMap) {
        n.adopt(m)
        nav = n
        navComing = nil
    }

    /// Whether it can get to `a` at all, as far as it knows: in its tank, by
    /// its ways (by what meets what, while they are being worked out).
    private func canGet(to a: Anchor) -> Bool {
        guard inHabitat, !map.loops.isEmpty, mode == .attached else { return true }
        if let n = tankNav() { return n.canReach(from: anchor, dir: walkDir, to: a) }
        return a.loopID == anchor.loopID || firstHops(from: anchor.loopID, to: a.loopID) != nil
    }

    /// `canGet`, to ask of one place after another (worked out once for all
    /// of them). While its ways are being worked out, anywhere will do.
    private func gettable() -> (Anchor) -> Bool {
        guard inHabitat, !map.loops.isEmpty, mode == .attached, let n = tankNav() else { return { _ in true } }
        return n.reachable(from: anchor, dir: walkDir)
    }

    /// Whether it can get to where a creature is, in its tank.
    private func canGet(to p: Prey) -> Bool {
        guard inHabitat, let a = p.anchor else { return true }
        return canGet(to: a)
    }

    /// What getting about costs it just now (see `NavLean`).
    private func navLean(_ n: TankNav, _ trip: NavTrip, hurry: Bool) -> NavLean {
        var l = NavLean()
        l.leap = Float(lerp(1.35, 0.72, personality.bravery)) * trip.leapMood * (hurry || huntTarget != nil ? 0.85 : 1)
        if placesOn, let know = knowledge {
            let id = ObjectIdentifier(n)
            if let h = navHopLean, h.nav == id, t - h.at < 5 {
                l.hops = h.hops
            } else {
                l.hops = n.hops.map { Float(1 - 0.35 * know.route($0.key)) }
                navHopLean = (id, t, l.hops)
            }
        }
        // (In a gale, not by way of what sways in it if there is any other.)
        if eco != nil, abs(weather.wind) > 0.55, let tank {
            let swaying = Set(tank.items.filter { $0.kind.sways }.map(\.id))
            l.keepOff = Set(n.owner.indices.filter { swaying.contains(n.owner[$0]) }.map { Int32($0) })
            l.keepOffCost = Float(1 + 2.5 * min(abs(weather.wind), 1.5))
        }
        l.penalty = trip.penalty
        return l
    }

    /// Off toward `goal` by the tank's ways: the next leg of the cheapest way
    /// there — a walk (over onto the next surface, and on, where the way
    /// goes over), a leap, a door. Nil where it has no ways to go by (the
    /// desktop): then it goes by the surfaces alone.
    private func navGo(to goal: Anchor, within: CGFloat, style: Activity) -> Headway? {
        guard inHabitat, !map.loops.isEmpty else { return nil }
        guard mode == .attached, map.loop(goal.loopID) != nil else { return .noWay }
        // There already.
        if goal.loopID == anchor.loopID, let way = loopWay(to: goal), way.dist <= within {
            navTrip = nil
            return .there
        }
        guard let n = tankNav() else {
            // (Its ways are being worked out for the tank as it is now: a
            // moment's look about.)
            walkGoal = nil
            routeHop = nil
            beginActivity(.look, dur: 0.35)
            return .going
        }
        let sc = config.scale
        let gp = map.worldPoint(goal) ?? pos
        var trip: NavTrip
        if let tr = navTrip, tr.nav == ObjectIdentifier(n), tr.goal.loopID == goal.loopID, tr.point.distance(to: gp) < 40 * sc {
            trip = tr
        } else {
            trip = NavTrip(goal: goal, within: within, point: gp, nav: ObjectIdentifier(n), leapMood: Float(randRange(0.85, 1.2)), bestAt: t)
        }
        trip.goal = goal
        trip.point = gp
        trip.within = within
        trip.hops = []
        trip.hopEdges = []
        // How the last leg went: a leap never made (called off — twice, and
        // it is not on from here); one that came down somewhere else is not
        // to be counted on; a door that did not open for it.
        var foundOut = false
        if let lp = trip.leap {
            trip.leap = nil
            if launches == lp.launches {
                trip.penalty[lp.edge] = (trip.penalty[lp.edge] ?? 0) >= 600 ? .infinity : 600
                foundOut = true
            } else {
                let want = n.nodes[Int(n.leaps[Int(n.edges[Int(lp.edge)].ref)].to)]
                let ok = n.locate(anchor).map { $0.loop == Int(want.loop) && abs($0.along - want.along) <= 45 } ?? false
                if !ok {
                    trip.penalty[lp.edge, default: 0] += 300
                    foundOut = true
                }
            }
        }
        if let dr = trip.door {
            trip.door = nil
            if pos.distance(to: dr.from) < 40 * sc {
                trip.penalty[dr.edge] = .infinity
                foundOut = true
            }
        }
        // (Found out something about the way: how near it is getting is
        // measured afresh, on the way it goes now.)
        if foundOut {
            trip.bestLeft = .infinity
            trip.bestAt = t
        }
        let hurry = style == .scurry
        guard var plan = n.plan(from: anchor, dir: walkDir, to: goal, within: within, lean: navLean(n, trip, hurry: hurry)) else {
            navTrip = nil
            return .noWay
        }
        // Getting no nearer for a good while: whatever it is stuck on costs
        // more; and after a few goes at it, it gives up.
        if plan.cost < trip.bestLeft - 20 {
            trip.bestLeft = plan.cost
            trip.bestAt = t
        } else if t - trip.bestAt > 14 {
            trip.strikes += 1
            trip.bestAt = t
            trip.bestLeft = .infinity
            guard trip.strikes <= 3 else { navTrip = nil; return .noWay }
            if let e = plan.vias.dropFirst().first(where: { $0 >= 0 }) {
                trip.penalty[e, default: 0] += 400
                guard let again = n.plan(from: anchor, dir: walkDir, to: goal, within: within, lean: navLean(n, trip, hurry: hurry)) else {
                    navTrip = nil
                    return .noWay
                }
                plan = again
            }
        }
        // At a spot of the goal's already (on something right by it, say).
        if plan.direct == nil, plan.states.count == 1, plan.vias.first ?? -1 < 0, plan.cost <= Float(max(within, 3) + 2) {
            navTrip = nil
            return .there
        }
        guard let leg = n.leg(of: plan, from: anchor) else {
            navTrip = nil
            return .noWay
        }
        headDist = CGFloat(plan.cost)
        if Spider.debugNavPlans {
            let at = n.locate(anchor).map { String(format: "%@@%.0f%@", anchor.loopID, Double($0.along), walkDir > 0 ? "+" : "-") } ?? "?"
            print("          plan from \(at): \(n.describe(plan))")
        }
        lastLeg = (leg, plan.cost, plan.states.count)
        switch leg {
        case .walk(let dir, let to, let w, let hops, let hopEdges, let length):
            walkGoal = (to, w)
            routeHop = hops.first
            trip.hops = hops
            trip.hopEdges = hopEdges
            lookAhead(dir)
            let pace = max(config.walkSpeed * (style == .scurry ? 1.9 : style == .sneak ? 0.42 : 1) * 0.5, 1)
            turnTo(dir, then: style, for: min(length / pace + 2, 40))
        case .leap(let edge, let aim):
            walkGoal = nil
            routeHop = nil
            trip.leap = (edge, pos, launches)
            startJump(to: aim)
        case .door(let edge, let at):
            walkGoal = nil
            routeHop = nil
            trip.door = (edge, pos)
            turnTo(walkDirToward(at), then: .walk, for: 1.6)
        }
        navTrip = trip
        navLive = true
        return .going
    }

    /// Tools: its ways about the tank, and the trip it is on.
    var debugNav: TankNav? { tankNav() }
    func debugCanGet(to p: Prey) -> Bool { canGet(to: p) }
    func debugCanGet(to a: Anchor) -> Bool { canGet(to: a) }
    /// The leg it set off on last: what, and of how long a way (in `navGo`'s
    /// costs), in how many steps.
    private var lastLeg: (leg: TankNav.Leg, cost: Float, steps: Int)?
    /// Tools: every plan printed as it is made.
    static var debugNavPlans = false
    var debugNavTrip: String {
        guard let tr = navTrip else { return "-" }
        var leg = ""
        switch lastLeg?.leg {
        case .walk(let dir, let to, _, let hops, _, let length)?:
            leg = String(format: "walk %+.0f to %@/%d/%.0f over %d, %.0f", Double(dir), to.loopID, to.segIdx, Double(to.t), hops.count, Double(length))
        case .leap(_, let aim)?:
            leg = String(format: "leap to (%.0f,%.0f)", Double(aim.x), Double(aim.y))
        case .door?:
            leg = "door"
        case nil:
            break
        }
        return String(format: "strikes %d penalties %d%@: %@ (of %.0f, %d steps)", tr.strikes, tr.penalty.count, navLive ? " live" : "", leg,
                      Double(lastLeg?.cost ?? 0), lastLeg?.steps ?? 0)
    }

    /// Just gone over onto the next surface of its way: on along it if the
    /// goal is ahead on this one, else a stop to take the next step.
    private func replanAfterHop() {
        guard [.walk, .sneak, .scurry].contains(activity) else { return }
        // By the tank's ways: on to the next way over on this leg, if there
        // is one, and on to where the leg ends.
        if navLive, var trip = navTrip {
            if !trip.hops.isEmpty { trip.hops.removeFirst() }
            if !trip.hopEdges.isEmpty { trip.hopEdges.removeFirst() }
            routeHop = trip.hops.first
            navTrip = trip
            return
        }
        // (On along it only if that is the way to go: not the long way round.)
        if let g = walkGoal, g.anchor.loopID == anchor.loopID, let loop = map.loop(anchor.loopID),
           let dd = loopDistance(loop, to: g.anchor, dir: walkDir), let way = loopWay(to: g.anchor), dd <= way.dist * 1.2 + 20 * config.scale {
            activityDur = activityTime + dd / max(config.walkSpeed * 0.3, 1) + 0.5
        } else {
            activityDur = min(activityDur, activityTime + 0.1)
        }
    }

    /// Tools only: what it is up to with the things in the tank.
    var debugInquiry: String {
        guard let q = inquiry else { return exploring ? "exploring" : "-" }
        let a = knowledge?.acquaintance(q.uid)
        return String(format: "%@ %@ todo [%@] done [%@] exp %.2f unease %.2f%@", q.stage.rawValue, q.doing ? "doing" : "",
                      q.todo.map(\.rawValue).joined(separator: ","), q.done.map(\.rawValue).joined(separator: ","),
                      Double(a?.exposure ?? 0), Double(a?.unease ?? 0), riding != nil ? " riding" : "")
    }
    /// Tools only: the thing it is looking into, and the thing under its feet.
    var debugInquiryUID: String? { inquiry?.uid }
    /// Tools only: the last thing it noticed, where, and how readily.
    private(set) var debugLastNotice = ""
    var debugWalk: String {
        let d = map.seg(anchor)?.dir ?? .zero
        return String(format: "walkDir %.0f pending %.0f seg %d dir %.2f,%.2f", Double(walkDir), Double(pendingDir), anchor.segIdx, Double(d.x), Double(d.y))
    }
    var debugUnderfoot: Int? { underfoot }
    var debugFeelAt: V2? { activity == .feel ? feelAt : nil }
    var debugEyeOn: V2? { t < eyeOnUntil ? eyeOn : nil }

    // MARK: Places in the tank
    //
    // What its tank is good for (HabitatPlaces.swift), and making use of it:
    // to the water it knows for a drink when it feels like one; in under
    // cover when it comes down hard, or into somewhere shut in after a
    // fright; up somewhere high to look out over it all; back to where it
    // likes to rest, and to sleep; to the warm; round its favourite spots.
    //
    // None of it is a need. Nothing goes wrong for going without, and
    // nothing of it is ever shown: there is what it gets to feeling like
    // (`urges`, building up in their own time), what is going on round it
    // (the weather, a fright, you, prey about) and what it has come to like
    // — every place it uses, and how that went, is remembered
    // (HabitatKnowledge.swift), and it goes back to what went well, by the
    // ways that got it there before, so it comes to have its favourites for
    // you to find out by watching. And it improvises: another good spot now
    // and then instead of the usual, a leap where the way round is long.
    //
    // Each is an errand: somewhere to get to (`travel`: along the surfaces
    // and over onto the next, a leap where there is no other way, in
    // through a door) and then what it does there (`act`), one step at a
    // time, between its ordinary decisions.

    /// Its tank's places as laid out now: sized up the first time they are
    /// wanted after each layout.
    private var survey: PlaceSurvey?
    /// In a tank, with a mind of its own about it.
    private var placesOn: Bool { inHabitat && tank != nil && knowledge != nil }

    private enum ErrandKind: String {
        case drink, dew, shelter, hide, sleep, rest, lookout, bask, perch, revisit, mirror, explore, glass, watch, ambush, mealSite, round
        /// (The tank as a living place: see "The tank alive", below.)
        case emerge, shade, forage

        var use: PlaceUse? {
            switch self {
            case .drink: return .drink
            case .shelter: return .shelter
            case .hide: return .hide
            case .sleep: return .sleep
            case .rest, .shade: return .rest
            case .lookout: return .lookout
            case .bask: return .bask
            case .perch: return .perch
            case .ambush, .forage: return .hunt
            default: return nil
            }
        }
        /// Put off for something new it has just noticed.
        var yields: Bool { ![.drink, .dew, .shelter, .hide, .sleep].contains(self) }
    }
    private enum ErrandStage: String { case travel, act }
    private struct Errand {
        var kind: ErrandKind
        var place: HabitatPlace
        var stage: ErrandStage = .travel
        var since: CGFloat
        var stageSince: CGFloat
        /// How far into what it does there.
        var step = 0
        /// Staying until then.
        var until: CGFloat = 0
        /// There, within this of it along the surface.
        var within: CGFloat
        var hurry = false
        /// Getting there: set off from `lastPos`, and how often it has got
        /// nowhere, leapt, tried a door.
        var went = false
        var lastPos = V2.zero
        var stalls = 0, leaps = 0, doors = 0
        /// The ways over from one surface to the next it took (`routeKey`).
        var hops: [String] = []
        /// What went wrong while it was about it (a fright, woken).
        var upset: CGFloat = 0
        /// Hiding from.
        var threat: V2?
        /// On round its places: where next.
        var then: [HabitatPlace] = []
        /// At the water: what more it means to do than drink (see `act`).
        var goes: [Int] = []
        var plays = 0
        /// Where it looks, or puts its mouth.
        var aim: V2?
        /// The tank was laid out again under it: the place, as it is now.
        var stale = false
        /// A drop of rain on a leaf it is after (`Droplet.id`), and where a
        /// front leg goes to turn out what may be lying low there.
        var drop: Int?
        var probe: V2?
    }
    private var errand: Errand?
    private var errandRestUntil: CGFloat = 0
    private var lastErrand: [ErrandKind: CGFloat] = [:]
    /// What it gets to feeling like, in its own time — a drink, a look out
    /// over it all, a rest, a wander somewhere it hasn't been — 0 just had,
    /// past 1 wanting it. Never shown; nothing comes of going without.
    private struct Urges { var thirst: CGFloat = 0, view: CGFloat = 0, rest: CGFloat = 0, roam: CGFloat = 0, set = false }
    private var urges = Urges()
    /// Its last fright in the tank: when, and where from.
    private var lastFright: (at: CGFloat, from: V2)?
    private var lastRainAt: CGFloat = -9999
    /// The place it is at (`HabitatPlace.key`), and for how long.
    private var placeAt: String?
    private var placeFor: CGFloat = 0
    private var placeCounted = false
    private var sightingIn: CGFloat = 0
    /// Drinking (`.drink`): where its mouth goes — open water (rings spread
    /// from it) or a drop on a leaf.
    private var sipAt: V2?
    private var sipWater = false
    /// A front leg at the water: rings spread from it.
    private var waterTouch: V2?
    private var rippleIn: CGFloat = 0

    private func uid(of id: Int) -> String? { id == 0 ? nil : tank?.item(id: id)?.uid }

    private func places() -> PlaceSurvey? {
        guard placesOn, let tank else { return nil }
        if survey == nil || surveyMap != ObjectIdentifier(map) {
            survey = PlaceSurvey(tank, map: map, scale: config.scale)
            surveyMap = ObjectIdentifier(map)
        }
        return survey
    }
    /// The surfaces it was sized up on.
    private var surveyMap: ObjectIdentifier?

    private func wakeUrges() {
        guard !urges.set else { return }
        urges = Urges(thirst: randRange(0.1, 0.55), view: randRange(0, 0.4), rest: randRange(0, 0.5), roam: randRange(0, 0.4), set: true)
    }

    /// Every frame in the tank: its urges, in their own time.
    private func livePlaces(dt: CGFloat) {
        wakeUrges()
        let P = personality, w = weather
        urges.thirst = min(1.6, urges.thirst + dt / lerp(820, 520, P.energy) * (1 + w.heat * 1.5 + w.sun * 0.3) * (w.rain > 0.2 ? 0.4 : 1)
                           * (activity == .scurry ? 1.5 : 1))
        urges.view = min(1.4, urges.view + dt / lerp(640, 360, P.curiosity))
        urges.roam = min(1.4, urges.roam + dt / lerp(760, 380, P.curiosity))
        if [.rest, .sleep, .bask].contains(activity) {
            urges.rest = max(0, urges.rest - dt / (errand == nil ? 70 : 25))
        } else {
            urges.rest = min(1.6, urges.rest + dt / lerp(560, 260, P.laziness) * lerp(1, 1.8, drowsy))
        }
        if w.rain > 0.15 { lastRainAt = t }
        liveEcology(dt: dt)
        if isHeld, let e = errand {
            // Picked up: whatever it was about is over — and a nap cut short
            // is no good nap.
            errand!.upset += [.sleep, .rest, .hide].contains(e.kind) && e.stage == .act ? 0.8 : 0
            endErrand(how: e.stage == .act ? 0.2 : 0)
        }
    }

    /// A few times a second in the tank: where it is, and what it makes of it.
    private func placesTick(_ tick: CGFloat) {
        guard let know = knowledge, let sv = places() else { return }
        know.tick(tick)
        guard mode == .attached, !isHeld else { placeAt = nil; return }
        let sc = config.scale
        guard let pl = sv.nearest(to: pos, within: 18 * sc) else { placeAt = nil; return }
        if pl.key != placeAt {
            placeAt = pl.key
            placeFor = 0
            placeCounted = false
        }
        placeFor += tick
        let still = speed < 3
        if still, placeFor >= 2.5, !placeCounted {
            placeCounted = true
            know.stopped(at: pl.key, pl.point, uid: uid(of: pl.owner))
        }
        // Settled there in peace: it grows on it, and on what it is on.
        if still, [.rest, .sleep, .bask].contains(activity) {
            know.settled(at: pl.key, pl.point, uid: uid(of: pl.owner), for: activity == .sleep ? .sleep : .rest, secs: tick)
        }
        if still, pl.owner != 0, [.rest, .sleep, .bask, .look, .groom].contains(activity), let it = tank?.item(id: pl.owner) {
            know.warm(to: it, by: tick / 60 * 0.03)
        }
        // Prey about: where it comes.
        sightingIn -= tick
        if sightingIn <= 0 {
            sightingIn = 2
            for p in prey where p.state == .loose && p.noticed && p.pos.distance(to: pos) < 500 * sc {
                if let at = sv.nearest(to: p.pos, within: 60 * sc) { know.sawPrey(at: at.key, at.point, uid: uid(of: at.owner)) }
            }
        }
        ecologyTick(tick)
    }

    /// A fright in the tank (from `p`): remembered where it happened, and
    /// whatever it was about is over — hiding, or under cover, it stays put.
    private func noteFright(from p: V2) {
        guard placesOn else { return }
        lastFright = (t, p)
        if let sv = places(), let pl = sv.nearest(to: pos, within: 30 * config.scale) {
            knowledge?.fright(at: pl.key, pl.point, uid: uid(of: pl.owner))
        }
        guard let e = errand else { return }
        errand!.upset += 0.6
        if ![.hide, .shelter].contains(e.kind) { endErrand(how: 0) }
    }

    /// A catch, at `p`: somewhere prey comes.
    private func noteCatch(at p: V2) {
        guard placesOn, let sv = places(), let pl = sv.nearest(to: p, within: 60 * config.scale) ?? sv.nearest(to: pos, within: 60 * config.scale) else { return }
        knowledge?.caught(at: pl.key, pl.point, uid: uid(of: pl.owner))
    }

    /// Somewhere for `use` it knows of, as it sees it now: mostly the best,
    /// now and then — the curious the more — another good one, to see.
    private func choose(_ use: PlaceUse, threat: V2? = nil, only: ((HabitatPlace) -> Bool)? = nil) -> HabitatPlace? {
        guard let sv = places(), let tank, let know = knowledge else { return nil }
        let sc = config.scale
        let known = Set(tank.items.filter { know.stage(of: $0.uid) != .unknown }.map(\.id))
        let uids = Dictionary(tank.items.map { ($0.id, $0.uid) }, uniquingKeysWith: { a, _ in a })
        let w = weather
        let want = PlaceWant(use: use, from: pos, scale: sc, personality: personality, threat: threat, rough: w.rough, sun: w.sun)
        let bustle: V2? = cursorVel.length > 250 ? cursor : nil
        let stirred = stirring.keys.compactMap { tank.item(id: $0)?.rect.insetBy(dx: -120 * sc, dy: -120 * sc) }
        // The tank alive: stone warm from the sun; prey coming by (for a
        // hunt); in a gale, what sways and what is up high out in it.
        let eco = self.eco
        let loose = use == .hunt ? prey.filter { $0.state == .loose && $0.noticed }.map(\.pos) : []
        let gale = eco == nil ? 0 : clamp((abs(w.wind) - 0.45) / 0.6, 0, 1)
        let swaying = gale > 0 ? Set(tank.items.filter { $0.kind.sways }.map(\.id)) : []
        let reachable = gettable()
        let ranked = sv.ranked(want) { pl in
            // (Nothing on, over or about a thing it hasn't noticed.)
            for id in [pl.owner, pl.thing, pl.roofOwner] where id != 0 && !known.contains(id) { return nil }
            if let only, !only(pl) { return nil }
            // (Nor anywhere it has no way to get to.)
            if !reachable(pl.anchor) { return nil }
            var s = PlaceSense(record: know.record(pl.key))
            if pl.thing != 0, let u = uids[pl.thing] { s.thingFond = know.acquaintance(u)?.fond ?? 0 }
            if let b = bustle, b.distance(to: pl.point) < 160 * sc { s.disturbance += 0.5 }
            if stirred.contains(where: { $0.contains(pl.point.point) }) { s.disturbance += 0.4 }
            if let eco {
                if pl.standing { s.warm = eco.warmth[pl.owner] ?? 0 }
                if use == .hunt { s.prey = eco.preyPull(at: pl.point, loose: loose) }
                if gale > 0 {
                    // (In a real gale, nothing that sways in it at all.)
                    if swaying.contains(pl.owner) {
                        if gale > 0.5 { return nil }
                        s.disturbance += 0.6 * gale
                    }
                    s.disturbance += 0.35 * gale * pl.q[.exposure] * pl.q[.elevation]
                }
            }
            return s
        }
        // Its favourite for this, if it has one and it is still good for it:
        // mostly back there, the fonder of it the likelier — from right
        // across the tank if need be.
        // (Only if it is about as good in itself as the best of the rest,
        // wherever each is: a table top it took to once is no lookout
        // beside a real one.)
        func itself(_ pl: HabitatPlace, _ r: PlaceRecord?) -> CGFloat {
            var w = want
            w.from = pl.point
            var s = PlaceSense(record: r)
            if let eco, pl.standing { s.warm = eco.warmth[pl.owner] ?? 0 }
            return sv.appeal(pl, w, s)
        }
        if use != .hide, let f = know.favourite(for: use, where: { sv.place($0) != nil }), let fav = sv.place(f.key),
           [fav.owner, fav.thing, fav.roofOwner].allSatisfy({ $0 == 0 || known.contains($0) }), only?(fav) ?? true, reachable(fav.anchor) {
            let mine = itself(fav, f.record)
            let best = ranked.reduce(CGFloat(0)) { max($0, itself($1.place, know.record($1.place.key))) }
            let worth = best > 0 ? min(1, mine / best) : 1
            if mine > 0.05, chance((0.45 + 0.45 * f.record.fond(use)) * worth / (1 + fav.point.distance(to: pos) / (3000 * sc))) {
                return fav
            }
        }
        guard let top = ranked.first else { return nil }
        if ranked.count > 1, chance(lerp(0.04, 0.2, personality.curiosity)) {
            return ranked[min(Int(randRange(1, CGFloat(min(ranked.count, 5)))), ranked.count - 1)].place
        }
        let weights = ranked.map { pow($0.score / top.score, 4) }
        var r = randRange(0, weights.reduce(0, +))
        for (wt, c) in zip(weights, ranked) {
            if r <= wt { return c.place }
            r -= wt
        }
        return top.place
    }

    /// Off to `pl` for `kind`. True if it set off (or is there already).
    @discardableResult
    private func startErrand(_ kind: ErrandKind, at pl: HabitatPlace, hurry: Bool = false, threat: V2? = nil, within: CGFloat? = nil,
                             then: [HabitatPlace] = [], drop: Int? = nil, probe: V2? = nil) -> Bool {
        guard mode == .attached, !isHeld else { return false }
        // (Not up onto something swaying in a gale, whatever for.)
        if eco != nil, abs(weather.wind) > 0.75, kind != .drink, let it = tank?.item(id: pl.owner), it.kind.sways {
            debugPlaceNote = "not up that in this wind"
            return false
        }
        if errand != nil { endErrand(how: 0) }
        errand = Errand(kind: kind, place: pl, since: t, stageSince: t, within: within ?? 6 * config.scale, hurry: hurry, lastPos: pos,
                        threat: threat, then: then)
        errand?.drop = drop
        errand?.probe = probe
        lastErrand[kind] = t
        queued = nil
        walkThen = nil
        coverGoal = nil
        if pl.thing != 0, let it = tank?.item(id: pl.thing) { knowledge?.visited(it) }
        if !pursueErrand() { return errand != nil }
        return true
    }

    /// Done with it — `how` it went: 1 just right, 0 nothing to it, -1 badly.
    private func endErrand(how: CGFloat, _ caller: String = #function, _ line: Int = #line) {
        guard let e = errand else { return }
        debugErrandEnd = "\(e.kind.rawValue) (step \(e.step)) ended by \(caller):\(line)"
        errand = nil
        walkGoal = nil
        routeHop = nil
        feelAt = nil
        sipAt = nil
        sipDrop = nil
        waterTouch = nil
        eyeOnUntil = min(eyeOnUntil, t + 0.8)
        if let use = e.kind.use, e.stage == .act || how < 0 {
            knowledge?.used(e.place.key, e.place.point, uid: uid(of: e.place.owner), for: use, how: how - e.upset)
        }
        knowledge?.travelled(e.hops, ok: false)
        errandRestUntil = t + randRange(6, 18) * lerp(1.4, 0.7, personality.energy)
    }

    /// One decision's worth of it. False once it is over, for now.
    private func pursueErrand() -> Bool {
        guard var e = errand else { return false }
        // (In the air, or dangling: once it is down, on with it.)
        guard mode == .attached else { return true }
        decisionIn = randRange(0.3, 0.6)
        if e.stale {
            guard let pl = places()?.place(e.place.key) else { endErrand(how: 0); return false }
            e.place = pl
            e.stale = false
            if e.stage == .travel { e.went = false }
        }
        // Something new, just noticed: that first, unless this matters more.
        if e.kind.yields, freshlyNoticed != nil {
            endErrand(how: 0)
            return false
        }
        // Caught out in it on the way to something else: the weather first.
        if weather.rough || worried, !sheltered, ![.shelter, .hide].contains(e.kind), !(e.kind == .sleep && e.place.q[.cover] > 0.5) {
            endErrand(how: 0)
            return false
        }
        // (On something swaying in a gale: off it first.)
        if eco != nil, shakenByGale, ![.shelter, .hide, .drink].contains(e.kind) {
            endErrand(how: 0)
            return false
        }
        switch e.stage {
        case .travel:
            if t - e.stageSince > ([.sleep, .round, .shelter].contains(e.kind) ? 150 : 90) {
                errand = e
                endErrand(how: -0.3)
                return false
            }
            switch travel(&e) {
            case .going:
                errand = e
                return true
            case .noWay where e.kind == .emerge:
                // (No way out to the open from here: a look round from where
                // it is, all the same.)
                e.stage = .act
                e.stageSince = t
                e.step = 0
                walkGoal = nil
                routeHop = nil
            case .noWay:
                // (A drop it could find no way to: the ones on that, let be
                // a while — there are others.)
                if e.kind == .dew {
                    noWayToDrops = noWayToDrops.filter { $0.value > t }
                    noWayToDrops[e.place.thing] = t + 150
                }
                errand = e
                endErrand(how: -0.4)
                return false
            case .there:
                e.stage = .act
                e.stageSince = t
                e.step = 0
                walkGoal = nil
                routeHop = nil
                // It stops here: noted, and so is the way that got it here.
                knowledge?.stopped(at: e.place.key, e.place.point, uid: uid(of: e.place.owner))
                knowledge?.travelled(e.hops, ok: true)
                e.hops = []
                placeAt = e.place.key
                placeFor = 0
                placeCounted = true
            }
        case .act:
            break
        }
        let more = act(&e)
        decisionIn = 0.05
        errand = e
        if !more {
            endErrand(how: 1)
            // (And straight on to what that led to: out from cover, to a drop.)
            if let next = chainNext {
                chainNext = nil
                _ = next()
            }
        }
        return true
    }
    /// What one errand, done, leads straight on to.
    private var chainNext: (() -> Bool)?

    /// Onward to the place: along the surfaces and over onto the next; a
    /// leap where there is no walking there — or, now and then, just
    /// because the way round is long; in through a door, if one is shut.
    private func travel(_ e: inout Errand) -> Headway {
        let sc = config.scale
        let goal = e.place.anchor
        if pos.distance(to: e.place.point) < max(e.within, 6 * sc) + 2 * sc { return .there }
        // In the tank, by its ways: a leap where a leap is the way (see
        // "Its ways about the tank").
        if let way = navGo(to: goal, within: e.within, style: e.hurry ? .scurry : .walk) {
            e.went = way == .going
            return way
        }
        if e.went { e.stalls = pos.distance(to: e.lastPos) < 4 * sc ? e.stalls + 1 : 0 }
        let first = !e.went && e.stalls == 0 && t - e.stageSince < 0.5
        e.went = false
        e.lastPos = pos
        if e.stalls > 3 {
            // Getting nowhere: a leap, if it can make one.
            guard e.leaps < 3, let p = leapTo(e.place) else { return .noWay }
            e.leaps += 1
            e.stalls = 0
            startJump(to: p)
            e.went = true
            return .going
        }
        if first, e.leaps == 0, goal.loopID != anchor.loopID, chance(lerp(0.04, 0.3, personality.bravery) * (e.hurry ? 1.5 : 1)),
           let p = leapTo(e.place) {
            e.leaps += 1
            startJump(to: p)
            e.went = true
            return .going
        }
        let style: Activity = e.hurry ? .scurry : .walk
        switch headFor(goal, style: style, within: e.within) {
        case .there:
            return .there
        case .going:
            // The only way on foot is the long way round (the way onto it
            // is from its far side): a leap, if it can — else not worth it.
            // (A real way round into a house is three times as far; round
            // the whole rim of the tank, under the lid, never is.)
            let straight = pos.distance(to: e.place.point)
            if headDist > max(straight * 4, straight + 1200 * sc) || (eco != nil && headDist > straight + 1800 * sc) {
                walkGoal = nil
                routeHop = nil
                queued = nil
                if [.walk, .sneak, .scurry].contains(activity) { activityDur = min(activityDur, activityTime) }
                guard e.leaps < 3, let p = leapTo(e.place) else { return .noWay }
                e.leaps += 1
                startJump(to: p)
            }
            e.went = true
            return .going
        case .noWay:
            if e.leaps < 3, let p = leapTo(e.place) {
                e.leaps += 1
                startJump(to: p)
                e.went = true
                return .going
            }
            if e.doors < 4, throughDoor(&e) { return .going }
            return .noWay
        }
    }

    /// A leap onto the place from here, if it can make it.
    private func leapTo(_ pl: HabitatPlace) -> V2? {
        let p = pl.point
        guard p.distance(to: pos) < 340 * config.scale, ballistic(from: pos, to: p) != nil else { return nil }
        return p
    }

    /// The way there is shut: through a door, if one leads there — along to
    /// it, and into it (it opens for it: see `DoorKeeper`).
    private func throughDoor(_ e: inout Errand) -> Bool {
        guard let sv = places() else { return false }
        let sc = config.scale
        var best: (d: CGFloat, side: (anchor: Anchor, point: V2), door: PlaceSurvey.Door)?
        for dr in sv.doors {
            let dx = dr.rect.midX
            guard dr.rect.insetBy(dx: -600 * sc, dy: -300 * sc).contains(e.place.point.point) else { continue }
            for s in dr.sides {
                // (From the side away from where it is going.)
                guard (s.point.x - dx) * (e.place.point.x - dx) < 0 else { continue }
                guard s.anchor.loopID == anchor.loopID || firstHops(from: anchor.loopID, to: s.anchor.loopID) != nil else { continue }
                let d = s.point.distance(to: pos)
                if d < best?.d ?? .greatestFiniteMagnitude { best = (d, s, dr) }
            }
        }
        guard let b = best else { return false }
        e.doors += 1
        if b.d > 12 * sc {
            if headFor(b.side.anchor, style: .walk, within: 4 * sc) == .going { e.went = true; return true }
            if b.d > 40 * sc { return false }
        }
        // At it: on into the doorway.
        walkGoal = nil
        routeHop = nil
        turnTo(walkDirToward(V2(b.door.rect.midX, pos.y)), then: .walk, for: 1.6)
        e.went = true
        return true
    }

    /// Faces `p` along its surface, then `next`.
    private func faceThen(_ p: V2, _ next: Activity, for dur: CGFloat) {
        if let dir = alongEdge(to: p), dir != walkDir, abs((p - pos).dot(map.seg(anchor)?.dir ?? V2(1, 0))) > 3 * config.scale {
            turnTo(dir, then: next, for: dur)
        } else {
            beginActivity(next, dur: dur)
        }
    }

    /// The way it faces at a place (`HabitatPlace.along`), as a point ahead.
    private func ahead(of pl: HabitatPlace) -> V2 {
        pos + (map.seg(pl.anchor)?.dir ?? V2(1, 0)) * pl.along * 40 * config.scale
    }

    /// What there is to watch from where it is: you at the glass, prey,
    /// something moving, the sky — or nothing in particular.
    private func watchable() -> V2? {
        let sc = config.scale
        if let area = cursorArea, area.contains(cursor.point), cursor.distance(to: pos) < 800 * sc, chance(0.6) { return cursor }
        if let p = prey.filter({ $0.state == .loose && $0.pos.distance(to: pos) < 700 * sc }).min(by: { $0.pos.distance(to: pos) < $1.pos.distance(to: pos) }) {
            return p.pos
        }
        if let id = stirring.keys.first, let it = tank?.item(id: id) { return V2(it.rect.midX, it.rect.midY) }
        if !weather.isCalm, chance(0.4) {
            skyLook(2.5)
            return pos + V2(randRange(-120, 120), 300) * sc
        }
        return nil
    }

    /// What it does there, a step at a time. False once it is done.
    private func act(_ e: inout Errand) -> Bool {
        let sc = config.scale
        let P = personality
        switch e.kind {
        case .drink, .dew:
            // To the water: a look at it first; now and then more to it
            // than a drink — a long look, a front leg to it and the rings
            // spreading, its own face in it looking back; then down to it,
            // and a drink; a pause; a groom, perhaps.
            let w = e.aim ?? e.place.focus ?? ahead(of: e.place)
            switch e.step {
            case 0:
                if e.kind == .dew, let id = e.drop {
                    // A drop of rain on the leaf, really there: gone (drunk,
                    // dried, shaken off) — nothing to it; else the curious
                    // give it a touch first.
                    guard let d = ecology?.droplet(id: id) else { return false }
                    e.aim = d.p
                    if chance(lerp(0.1, 0.65, P.curiosity)) { e.goes.append(5) }
                } else if e.kind == .dew {
                    // (A drop beaded on the leaf just ahead of it.)
                    let fwd = (map.seg(anchor)?.dir ?? V2(1, 0)) * walkDir
                    e.aim = pos - surfaceNormal * map.standoff + fwd * 13 * sc + surfaceNormal * 1.5 * sc
                } else {
                    e.aim = w
                    if chance(0.35 * lerp(0.6, 1.3, P.curiosity)) { e.goes.append(0) }
                    if chance(lerp(0.15, 0.55, P.curiosity)) { e.goes.append(1) }
                    if chance(lerp(0.1, 0.35, P.curiosity)) { e.goes.append(2) }
                }
                look(at: e.aim!, for: 3)
                faceThen(e.aim!, .peer, for: randRange(1.0, 1.6))
                e.step = 1
            case 1:
                guard !e.goes.isEmpty else {
                    e.step = 2
                    return act(&e)
                }
                switch e.goes.removeFirst() {
                case 0:
                    // Watching the water.
                    look(at: w, for: 4)
                    beginActivity(.look, dur: randRange(2.0, 3.6))
                case 1:
                    // A front leg to it.
                    let touch = pos + (w - pos).clampedLength(30 * sc)
                    feelAt = touch
                    feelNormal = V2(0, 1)
                    waterTouch = touch
                    rippleIn = 0.35
                    look(at: touch, for: 2.5)
                    beginActivity(.feel, dur: randRange(1.3, 2.0))
                    e.goes.insert(3, at: 0)
                case 2:
                    // Nose down over it: a face looking back up.
                    look(at: V2(pos.x + (w.x - pos.x) * 0.5, w.y), for: 3)
                    beginActivity(.peer, dur: randRange(2.0, 3.0))
                    e.goes.insert(4, at: 0)
                case 3:
                    // The rings spreading: a start, a long look — or, a
                    // playful one, another go for the fun of it.
                    feelAt = nil
                    waterTouch = nil
                    if P.playfulness > 0.5, e.plays < 2, chance(0.6 * P.playfulness) {
                        e.plays += 1
                        e.goes.insert(1, at: 0)
                        beginActivity(.wiggle, dur: 0.6)
                    } else if P.bravery < 0.45, chance(0.7) {
                        startled.velocity = 3
                        setEmote(.surprise, 0.45)
                        look(at: w, for: 2)
                        beginActivity(.look, dur: randRange(1.0, 1.6))
                    } else {
                        look(at: w, for: 2.5)
                        beginActivity(.look, dur: randRange(1.2, 2.2))
                        if chance(0.3) { setEmote(.question, 0.8) }
                    }
                case 4:
                    // What looks back squares up to it: it squares up back —
                    // or, a timid one, it starts back from it.
                    if P.bravery > 0.45 || chance(0.3) {
                        beginActivity(.armsUp, dur: randRange(0.9, 1.3))
                        if chance(0.5) { setEmote(.exclaim, 0.6) }
                    } else {
                        startled.velocity = 4
                        beginActivity(.startle, dur: 0.5)
                        queue(.look, randRange(0.8, 1.3))
                    }
                case 5:
                    // A drop on a leaf: a front leg to it, to see what it is.
                    feelAt = w
                    feelNormal = V2(0, 1)
                    look(at: w, for: 2.5)
                    beginActivity(.feel, dur: randRange(1.0, 1.6))
                    e.goes.insert(6, at: 0)
                case 6:
                    // It wobbles — and now and then runs off the leaf
                    // altogether: a start, and a look where it went.
                    feelAt = nil
                    ripple(at: w, size: 1.1)
                    if let id = e.drop, chance(0.22) {
                        ecology?.shed(id)
                        startled.velocity = 3
                        setEmote(.surprise, 0.6)
                        look(at: w + V2(0, -40 * sc), for: 1.5)
                        beginActivity(.look, dur: randRange(0.9, 1.4))
                        e.step = 5
                        // (Another, near by: that one, then.)
                        if let eco = ecology, let d = eco.droplet(near: pos, within: 120 * sc), chance(0.4 + 0.5 * P.curiosity) {
                            chainNext = { self.goForDrop(d) }
                        }
                        return true
                    }
                    look(at: w, for: 2)
                    beginActivity(.peer, dur: randRange(0.8, 1.4))
                    if chance(0.3) { setEmote(.question, 0.8) }
                default:
                    break
                }
            case 2:
                // Down to it, and a drink — unless it only came to see its
                // water was there: a last look, and it is off.
                feelAt = nil
                waterTouch = nil
                if e.kind == .drink, urges.thirst < 0.15 {
                    look(at: w, for: 2)
                    beginActivity(.look, dur: randRange(1.0, 2.0))
                    e.step = 5
                    return true
                }
                if let id = e.drop, ecology?.droplet(id: id) == nil { return false }
                sipAt = w
                sipWater = e.kind == .drink
                let dur = e.kind == .drink ? randRange(4, 8) : randRange(2.2, 3.4)
                // (A real drop on the leaf goes down as it drinks: see
                // `liveEcology`. Otherwise one is there for it to sip.)
                sipDrop = e.drop
                if e.kind == .dew, e.drop == nil { drops.append(Drop(p: w, v: .zero, r: 1.9, kind: .water, life: dur + 0.4, floor: nil, gravity: 0, sip: true)) }
                // (Side on to it, head down: eyes held on the water right
                // under it would turn it round to face you.)
                eyeOn = nil
                eyeOnUntil = t
                faceThen(w, .drink, for: dur)
                e.step = 3
            case 3:
                // A pause after (and the last of the drop gone).
                sipAt = nil
                if let id = sipDrop { ecology?.sip(id, by: 99) }
                sipDrop = nil
                urges.thirst = e.kind == .drink ? 0 : max(0, urges.thirst - 0.5)
                look(at: w, for: 2)
                beginActivity(chance(0.4) ? .rest : .look, dur: randRange(1.0, 2.2))
                e.step = 4
            case 4:
                e.step = 5
                guard chance(0.55) else { return false }
                beginActivity(.groom, dur: randRange(1.4, 2.4))
            default:
                return false
            }

        case .shelter:
            // In out of it: turned to look out at it, and sat out there —
            // resting, watching it come down, grooming the wet off — until
            // it has been over a little while.
            if e.step == 0 {
                e.step = 1
                skyLook(1.5)
                faceThen(ahead(of: e.place), .look, for: randRange(1.0, 1.8))
                return true
            }
            // (Coming down again while it was coming out: back to waiting.)
            if weather.rough || worried, e.step >= 50 { e.step = 1 }
            if weather.rough || (eco != nil && weather.rain > 0.08) { e.until = 0 } else if e.until == 0 {
                // In the tank, how long it stays in after is its own: the
                // timid, and the lazy, the longer.
                e.until = t + randRange(6, 16) * (eco != nil ? lerp(2.6, 0.55, P.bravery) * lerp(0.8, 1.5, P.laziness) : 1)
            }
            if (e.until > 0 && t > e.until) || t - e.stageSince > 300 {
                guard eco != nil, t - e.stageSince <= 300 else { return false }
                // Out again: a look out from under it first, a look at the
                // sky — and out into the open.
                switch e.step {
                case ..<50:
                    e.step = 50
                    look(at: ahead(of: e.place) + V2(0, 30 * sc), for: 2)
                    faceThen(ahead(of: e.place), .peer, for: randRange(1.0, 1.8))
                case 50:
                    e.step = 51
                    skyLook(randRange(1.2, 2))
                    beginActivity(.look, dur: randRange(1.0, 1.8))
                default:
                    let from = e.place
                    chainNext = { self.goEmerge(from: from) }
                    return false
                }
                return true
            }
            // Still getting wet here: no good — somewhere else.
            if weather.rough, !sheltered, t - e.stageSince > 3 {
                e.upset += 1.2
                return false
            }
            if wet > 0.4 || snowOn > 0.3, t - lastShakeOff > 6, chance(0.5) {
                beginActivity(.shake, dur: 0.7)
                queue(.groom, randRange(1.2, 2.0))
            } else {
                let r = randRange(0, 1)
                if r < 0.45 {
                    beginActivity(.rest, dur: randRange(5, 12))
                } else if r < 0.75 {
                    skyLook(2.5)
                    beginActivity(.look, dur: randRange(1.5, 3))
                } else {
                    beginActivity(.groom, dur: randRange(1.4, 2.4))
                }
            }

        case .hide:
            // Tucked in, low, eyes on where the fright came from; a while
            // of that — the timid the longer — a careful look out, and it is
            // over it.
            let threat = e.threat ?? ahead(of: e.place)
            if e.step == 0 {
                e.step = 1
                look(at: threat, for: 3)
                faceThen(threat, .brace, for: randRange(1.6, 3.0))
                e.until = t + randRange(12, 36) * lerp(1.6, 0.6, P.bravery)
                return true
            }
            if t > e.until {
                guard e.step < 99 else { return false }
                e.step = 99
                look(at: threat, for: 2)
                beginActivity(.peer, dur: randRange(1.0, 1.6))
                return true
            }
            let r = randRange(0, 1)
            if r < 0.5 {
                beginActivity(.rest, dur: randRange(4, 8))
            } else if r < 0.85 {
                look(at: threat, for: 2.5)
                beginActivity(.look, dur: randRange(1.2, 2.2))
            } else {
                beginActivity(.groom, dur: randRange(1.2, 2.0))
            }

        case .sleep:
            // Settled in, a rest, and off to sleep; up again, stretched and
            // shaken out (see `finishActivity`), and that is that.
            switch e.step {
            case 0:
                e.step = 1
                faceThen(ahead(of: e.place), chance(0.5) ? .groom : .rest, for: randRange(1.4, 2.6))
            case 1:
                e.step = 2
                beginActivity(.rest, dur: randRange(3, 6))
            case 2:
                e.step = 3
                urges.rest = 0
                beginActivity(.sleep, dur: randRange(40, 140) * (0.7 + P.laziness) * (1 - 0.5 * hunger))
            default:
                return false
            }

        case .rest, .perch, .shade:
            // Settled there a while; on a perch, a look about from it first
            // (in the shade: out of a hot sun, a while).
            switch e.step {
            case 0:
                e.step = 1
                faceThen(ahead(of: e.place), .look, for: randRange(0.8, 1.6))
            case 1:
                e.step = 2
                if e.kind == .perch {
                    eyeOn = nil
                    beginActivity(.look, dur: randRange(1.5, 3))
                } else if chance(0.35) {
                    beginActivity(.groom, dur: randRange(1.4, 2.4))
                } else {
                    return act(&e)
                }
            case 2:
                e.step = 3
                beginActivity(.rest, dur: (e.kind == .perch ? randRange(6, 14) : randRange(8, 22)) * (0.7 + P.laziness))
            default:
                if e.kind == .rest { urges.rest = max(0, urges.rest - 0.5) }
                if e.place.owner != 0, let it = tank?.item(id: e.place.owner) { knowledge?.warm(to: it, by: 0.08) }
                return false
            }

        case .lookout, .watch, .ambush:
            // Settled, facing out over the best of the view; then a slow
            // look round — and whatever there is to watch: you, prey,
            // something moving, the sky. Lying in wait, eyes low and close.
            if e.step == 0 {
                e.step = 1
                let view = e.place.focus ?? ahead(of: e.place)
                e.until = t + (e.kind == .lookout ? randRange(25, 60) * lerp(0.8, 1.3, P.curiosity)
                               : e.kind == .ambush ? randRange(20, 45) * (1 + 0.8 * hunger) : randRange(14, 28))
                if e.kind == .lookout { urges.view = 0 }
                look(at: view, for: 2)
                faceThen(view, .look, for: randRange(1.4, 2.4))
                return true
            }
            guard t < e.until else { return false }
            e.step += 1
            if let c = watchable() {
                look(at: c, for: 3)
                beginActivity(.look, dur: randRange(1.8, 3.2))
                return true
            }
            if e.kind != .ambush, chance(0.2) {
                eyeOn = nil
                beginActivity(.rest, dur: randRange(3, 6))
                return true
            }
            // (A slow sweep across what is in front of it, one way and then
            // back, a little way further round each time.)
            let sweep: [CGFloat] = [-1.8, -1.3, -0.8, 0.8, 1.3, 1.8]
            let k = e.step % 12
            let a = sweep[k < 6 ? k : 11 - k] + randRange(-0.15, 0.15)
            let reach = e.kind == .ambush ? randRange(90, 220) : randRange(260, 520)
            look(at: pos + surfaceNormal.rotated(by: a) * reach * sc, for: 3.5)
            beginActivity(e.kind == .ambush && chance(0.3) ? .peer : .look, dur: randRange(2.0, 3.6))

        case .bask:
            guard e.step == 0 else { return false }
            e.step = 1
            beginActivity(.bask, dur: randRange(10, 26) * (0.7 + P.laziness))
            happy.velocity = 2

        case .revisit, .mirror, .mealSite:
            // A thing it likes, again: a feel of it, a look. Its face in a
            // mirror: squared up to, and drummed at. Where it had a meal: a
            // nose about the ground there.
            let f = e.place.focus ?? ahead(of: e.place)
            switch e.step {
            case 0:
                e.step = 1
                look(at: f, for: 3)
                if e.kind == .revisit, e.place.kind == .touch {
                    feelAt = f
                    feelNormal = (pos - f).normalized
                    faceThen(f, .feel, for: randRange(1.4, 2.2))
                } else {
                    faceThen(f, .peer, for: randRange(1.2, 2.2))
                }
            case 1:
                e.step = 2
                feelAt = nil
                switch e.kind {
                case .mirror:
                    beginActivity(.armsUp, dur: randRange(1.0, 1.5))
                    setEmote(chance(0.5) ? .question : .exclaim, 0.8)
                case .mealSite:
                    feelAt = pos - surfaceNormal * map.standoff + (map.seg(anchor)?.dir ?? V2(1, 0)) * walkDir * 14 * sc
                    feelNormal = surfaceNormal
                    beginActivity(.feel, dur: randRange(1.2, 1.8))
                default:
                    look(at: f, for: 2)
                    beginActivity(.look, dur: randRange(1.0, 2.0))
                }
            case 2:
                e.step = 3
                feelAt = nil
                if e.kind == .mirror {
                    if chance(0.5 * (0.5 + P.playfulness)) {
                        beginActivity(.drum, dur: randRange(2.2, 3.4))
                        setEmote(.note, 1.2)
                    } else {
                        beginActivity(.wiggle, dur: 0.8)
                    }
                } else {
                    beginActivity(.look, dur: randRange(0.8, 1.6))
                }
            default:
                if e.place.thing != 0, let it = tank?.item(id: e.place.thing) { knowledge?.warm(to: it, by: 0.04) }
                return false
            }

        case .explore:
            // Somewhere it hasn't been: a look about.
            switch e.step {
            case 0:
                e.step = 1
                eyeOn = nil
                beginActivity(.look, dur: randRange(1.2, 2.4))
            case 1:
                e.step = 2
                guard chance(0.4) else { return false }
                beginActivity(.peer, dur: randRange(1.0, 1.6))
            default:
                return false
            }

        case .glass:
            // Up to the glass: a peer out through it, front legs up against
            // it, a look at what is out there — you, if you are.
            let world = places()?.world ?? CGRect(x: pos.x - 1, y: 0, width: 2, height: 1)
            let left = e.place.point.x < world.midX
            let out = V2(pos.x + (left ? -400 : 400) * sc, pos.y + 20 * sc)
            switch e.step {
            case 0:
                e.step = 1
                look(at: out, for: 3)
                faceThen(out, .peer, for: randRange(1.2, 2.0))
            case 1:
                e.step = 2
                let wallX = left ? world.minX : world.maxX
                guard surfaceNormal.y > 0.8, abs(wallX - pos.x) < 45 * sc else { return act(&e) }
                feelAt = V2(wallX, pos.y + 6 * sc)
                feelNormal = V2(left ? 1 : -1, 0)
                look(at: out, for: 2.5)
                beginActivity(.feel, dur: randRange(1.2, 1.8))
            case 2:
                e.step = 3
                feelAt = nil
                if let a = cursorArea, !a.contains(cursor.point), (cursor.x - pos.x) * (out.x - pos.x) > 0 {
                    look(at: cursor, for: 3)
                } else {
                    look(at: out, for: 3)
                }
                beginActivity(.look, dur: randRange(1.6, 3.2))
            default:
                return false
            }

        case .emerge, .forage:
            return actAlive(&e)

        case .round:
            // Round its places: a moment at each, on to the next.
            if e.step == 0 {
                e.step = 1
                beginActivity(chance(0.25) ? .groom : .look, dur: randRange(1.0, 2.0))
                return true
            }
            guard !e.then.isEmpty else { return false }
            e.place = e.then.removeFirst()
            e.stage = .travel
            e.stageSince = t
            e.step = 0
            e.stalls = 0
            e.leaps = 0
            e.went = false
        }
        return true
    }

    // What it feels like doing next.

    /// With nothing else on: what it feels like doing in its tank, if
    /// anything — each weighed by what it has been feeling like, the
    /// weather, what it knows is there, and who it is. True if it set off.
    private func startTankGoal() -> Bool {
        guard places() != nil, let tank, mode == .attached, !isHeld, riding == nil, inquiry == nil else { return false }
        // (Caught out in a downpour: the weather first.)
        guard !((weather.rough || worried) && !sheltered) else { return false }
        wakeUrges()
        // (The rain over while it was in under something: out.)
        if let due = emergeDue, t > due {
            emergeDue = nil
            if sheltered, let sv = places(), let here = sv.nearest(to: pos, within: 40 * config.scale), goEmerge(from: here) { return true }
        }
        let P = personality
        let u = urges
        func since(_ k: ErrandKind) -> CGFloat { t - (lastErrand[k] ?? -9999) }
        var wants: [(CGFloat, () -> Bool)] = []
        if u.thirst > 0.3 { wants.append((3 * (u.thirst - 0.3), { self.goFor(.drink) })) }
        // Its water, now and then, just to see it is there.
        if u.thirst <= 0.3, since(.drink) > 400 { wants.append((0.25 * lerp(0.6, 1.4, P.curiosity), { self.goFor(.drink) })) }
        if let eco {
            // The tank alive (see "The tank alive"): rain on the leaves;
            // somewhere open to watch mild weather from; a poke about where
            // something might be lying low; stone warm from the sun.
            ecoWants(eco, into: &wants)
        } else if t - lastRainAt < 900, weather.rain < 0.1, since(.dew) > 90 {
            wants.append(((0.3 + u.thirst) * 0.7, { self.goForDew() }))
        }
        // (Gone a long while without, in its tank alive: less of a rest, and
        // the hunt sooner — see `hunger`.)
        let hungry = hunger
        if u.view > 0.35 { wants.append((2 * (u.view - 0.35) * lerp(0.6, 1.4, P.curiosity), { self.goFor(.lookout) })) }
        if u.rest > 0.35 { wants.append((1.6 * (u.rest - 0.35) * lerp(0.6, 1.5, P.laziness) * (1 - 0.5 * hungry), { self.goFor(.rest) })) }
        if u.rest > 1.0 { wants.append((1.2 * (u.rest - 1.0) * lerp(0.5, 1.6, P.laziness) * (1 - 0.7 * hungry), { self.goFor(.sleep) })) }
        if chill > 0.2 || (weather.sun > 0.45 && !sheltered) {
            wants.append((1.6 * chill + 0.5 * weather.sun * lerp(0.5, 1.5, P.laziness), { self.goFor(.bask) }))
        }
        if since(.perch) > 120 { wants.append((0.35 * lerp(0.6, 1.4, P.laziness), { self.goFor(.perch) })) }
        if since(.revisit) > 150 { wants.append((0.3 * lerp(0.4, 1.6, P.curiosity), { self.goRevisit() })) }
        if since(.mirror) > 300, tank.items.contains(where: { $0.kind == .mirror }) {
            wants.append((0.1 + 0.4 * (P.bravery + P.playfulness) / 2, { self.goToMirror() }))
        }
        if u.roam > 0.4 { wants.append((1.2 * (u.roam - 0.4) * lerp(0.4, 1.4, P.curiosity), { self.goExplore() })) }
        if since(.glass) > 240 {
            let out = cursorArea.map { !$0.contains(cursor.point) } ?? false
            wants.append((0.15 + 0.25 * P.curiosity + (out ? 0.3 : 0), { self.goToGlass() }))
        }
        if since(.watch) > 90 { wants.append((0.2 + (weather.isCalm ? 0 : 0.35) + (stirring.isEmpty ? 0 : 0.3), { self.goWatch() })) }
        if fed < 0.7, since(.ambush) > lerp(180, 40, hungry) {
            wants.append((0.6 * (1 - fed) * (1 + 2.5 * hungry) * lerp(0.6, 1.4, P.energy), { self.goFor(.hunt) }))
        }
        if since(.mealSite) > 300 { wants.append((0.3 * lerp(0.5, 1.5, P.curiosity), { self.goToMealSite() })) }
        if since(.round) > 300 { wants.append((0.3 * lerp(0.5, 1.5, P.energy), { self.goRound() })) }
        let total = wants.reduce(0) { $0 + $1.0 }
        guard total > 0.01, chance(total / (total + 1.8)) else {
            errandRestUntil = t + randRange(5, 12)
            return false
        }
        var pool = wants
        while !pool.isEmpty {
            var r = randRange(0, pool.reduce(0) { $0 + $1.0 })
            var k = 0
            while k < pool.count - 1, r > pool[k].0 { r -= pool[k].0; k += 1 }
            if pool[k].1() { return true }
            pool.remove(at: k)
        }
        errandRestUntil = t + randRange(5, 12)
        return false
    }

    /// Off to the best place it knows for `use`.
    private func goFor(_ use: PlaceUse) -> Bool {
        let kind: ErrandKind
        switch use {
        case .drink: kind = .drink
        case .rest: kind = .rest
        case .sleep: kind = .sleep
        case .lookout: kind = .lookout
        case .bask: kind = .bask
        case .perch: kind = .perch
        case .hunt: kind = .ambush
        case .shelter: kind = .shelter
        case .hide: kind = .hide
        }
        guard let pl = choose(use) else { return false }
        return startErrand(kind, at: pl, within: kind == .drink ? 3 * config.scale : 6 * config.scale)
    }

    /// Something big in the weather, and out in it: into the best cover it
    /// knows (the house first, if it has one); failing that, the nearest.
    private func seekShelter() -> Bool {
        guard let pl = choose(.shelter) else { return sheltered ? false : seekCover() }
        let w = weather
        return startErrand(.shelter, at: pl, hurry: w.hail > 0.1 || w.storm > 0.3 || w.rain > 0.6 || w.sand > 0.5)
    }

    /// Sheltering under something natural: over to built cover it knows,
    /// if there is some worth the trip.
    private func moveToBuiltShelter() -> Bool {
        guard let sv = places(), mode == .attached else { return false }
        let sc = config.scale
        if let here = sv.nearest(to: pos, within: 24 * sc), here.q[.made] >= 0.3 { debugPlaceNote = "built: here already"; return false }
        guard let pl = choose(.shelter, only: { $0.q[.made] >= 0.5 }) else { debugPlaceNote = "built: none"; return false }
        guard pl.point.distance(to: pos) > 40 * sc, pl.point.distance(to: pos) < 900 * sc else {
            debugPlaceNote = "built: too far/near \(Int(pl.point.distance(to: pos)))"
            return false
        }
        debugPlaceNote = "built: off to \(pl.key)"
        return startErrand(.shelter, at: pl, hurry: true)
    }

    /// After a fright: somewhere shut in, away from it, to get over it —
    /// the timid all but always, the bold hardly ever.
    private func startHiding(from p: V2) -> Bool {
        lastFright = nil
        guard chance(lerp(0.97, 0.1, personality.bravery)) else { debugPlaceNote = "shrugged it off"; return false }
        guard let pl = choose(.hide, threat: p) else { debugPlaceNote = "nowhere to hide"; return false }
        debugPlaceNote = "hiding at \(pl.key)"
        return startErrand(.hide, at: pl, hurry: true, threat: p)
    }
    /// Tools only: what came of its last fright in the tank, or its last
    /// look for built cover.
    private(set) var debugPlaceNote = ""

    /// After rain: drops beaded on a leaf, a frond, the moss — a sip from one.
    private func goForDew() -> Bool {
        guard let sv = places(), let tank, let know = knowledge else { return false }
        let sc = config.scale
        var best: (s: CGFloat, pl: HabitatPlace)?
        for pl in sv.places where pl.standing && pl.owner != 0 && pl.q[.exposure] > 0.35 {
            guard let it = tank.item(id: pl.owner), know.stage(of: it.uid) != .unknown else { continue }
            let m = it.kind.definition.traits.material
            guard [.leaf, .moss, .stem, .fungus].contains(m) || it.kind.definition.shelf == .plants else { continue }
            let d = pl.point.distance(to: pos)
            guard d < 900 * sc else { continue }
            let s = (1 + pl.q[.moisture]) / (1 + d / (400 * sc)) * randRange(0.8, 1.2)
            if s > best?.s ?? 0 { best = (s, pl) }
        }
        guard let b = best else { return false }
        return startErrand(.dew, at: b.pl)
    }

    /// Back to something it knows and likes the look of, that it hasn't
    /// been to in a while: a feel of it, a look.
    private func goRevisit() -> Bool {
        guard places() != nil, let tank, let know = knowledge else { return false }
        let sc = config.scale
        var best: (s: CGFloat, it: HabitatItem)?
        for it in tank.items where worthKnowing(it) {
            guard know.isFamiliar(it.uid), (know.sinceVisit(it.uid) ?? 99_999) > 600 else { continue }
            let d = distance(to: it)
            guard d < 1000 * sc else { continue }
            let s = (tank.qualities(of: it)[.interesting] + 0.4 * max(know.acquaintance(it.uid)?.fond ?? 0, 0)) / (1 + d / (400 * sc)) * randRange(0.7, 1.3)
            if s > best?.s ?? 0 { best = (s, it) }
        }
        // Where to be by it: in reach of it, or where it can take it in.
        guard let it = best?.it else { return false }
        let pts = it.interactionPoints(on: map).filter { ($0.kind == .touch || $0.kind == .inspect) && $0.stand != nil }
        guard let ip = pts.min(by: { ($0.kind == .touch ? 0 : 60) + ($0.standPoint ?? $0.point).distance(to: pos)
                                      < ($1.kind == .touch ? 0 : 60) + ($1.standPoint ?? $1.point).distance(to: pos) }),
              let a = ip.stand, let sp = ip.standPoint, let seg = map.seg(a) else { return false }
        var pl = HabitatPlace(key: "\(it.uid):\(ip.kind.rawValue)", kind: ip.kind, anchor: a, point: sp, facing: seg.facing,
                              owner: map.owner(of: a) ?? 0, thing: it.id)
        pl.focus = ip.point
        pl.along = ip.facing
        return startErrand(.revisit, at: pl)
    }

    /// Up to a mirror on the wall, below it, to see who is in it.
    private func goToMirror() -> Bool {
        guard let sv = places(), let tank else { return false }
        let sc = config.scale
        var best: (d: CGFloat, pl: HabitatPlace)?
        for m in tank.items where m.kind == .mirror {
            let r = m.rect
            guard V2(r.midX, r.midY).distance(to: pos) < 1400 * sc else { continue }
            for pl in sv.places where pl.standing && pl.point.x > r.minX - 20 * sc && pl.point.x < r.maxX + 20 * sc
                && pl.point.y < r.minY + 10 * sc && pl.point.y > r.minY - 160 * sc {
                var p = pl
                p.focus = V2(r.midX, r.midY)
                let d = pl.point.distance(to: pos) + (r.minY - pl.point.y)
                if d < best?.d ?? .greatestFiniteMagnitude { best = (d, p) }
            }
        }
        guard let b = best else { return false }
        return startErrand(.mirror, at: b.pl)
    }

    /// Somewhere in the tank it hasn't been yet (or not for a long while).
    private func goExplore() -> Bool {
        guard let sv = places(), let tank, let know = knowledge else { return false }
        let sc = config.scale
        let been = know.places.values.map(\.p)
        let known = Set(tank.items.filter { know.stage(of: $0.uid) != .unknown }.map(\.id))
        var best: (s: CGFloat, pl: HabitatPlace)?
        for (i, pl) in sv.places.enumerated() where i % 3 == 0 && pl.q[.access] > 0.5 && !pl.hanging {
            guard pl.owner == 0 || known.contains(pl.owner) else { continue }
            let d = pl.point.distance(to: pos)
            guard d > 150 * sc, d < 1600 * sc, !been.contains(where: { $0.distance(to: pl.point) < 160 * sc }) else { continue }
            let s = randRange(0.5, 1.5) / (1 + d / (700 * sc))
            if s > best?.s ?? 0 { best = (s, pl) }
        }
        guard let b = best else { return false }
        urges.roam = 0
        return startErrand(.explore, at: b.pl, within: 20 * sc)
    }

    /// Over to the glass at an end of the tank — the side you are on, if
    /// you are out past it.
    private func goToGlass() -> Bool {
        guard let sv = places() else { return false }
        let sc = config.scale
        let outside = cursorArea.map { !$0.contains(cursor.point) } ?? false
        var best: (s: CGFloat, pl: HabitatPlace)?
        for pl in sv.places where pl.glass && !pl.hanging {
            let d = pl.point.distance(to: pos)
            var s = randRange(0.6, 1.4) / (1 + d / (900 * sc))
            if outside, (cursor.x - sv.world.midX) * (pl.point.x - sv.world.midX) > 0 { s *= 2 }
            if s > best?.s ?? 0 { best = (s, pl) }
        }
        guard let b = best else { return false }
        return startErrand(.glass, at: b.pl, within: 4 * sc)
    }

    /// A while watching whatever is going on — from here, or from a spot
    /// near by with more of a view.
    private func goWatch() -> Bool {
        guard let sv = places() else { return false }
        let sc = config.scale
        var best: (s: CGFloat, pl: HabitatPlace)?
        for pl in sv.places where pl.standing && pl.point.distance(to: pos) < 350 * sc {
            let s = (pl.q[.visibility] + 0.3 * pl.q[.cover] + 0.2) * randRange(0.8, 1.2) / (1 + pl.point.distance(to: pos) / (250 * sc))
            if s > best?.s ?? 0 { best = (s, pl) }
        }
        guard let b = best else { return false }
        return startErrand(.watch, at: b.pl, within: 10 * sc)
    }

    /// Back to where it made a catch not long ago, for a nose about.
    private func goToMealSite() -> Bool {
        guard let sv = places(), let know = knowledge else { return false }
        let recent = know.places.filter { $0.value.catches > 0.3 && know.clock - $0.value.last < 1800 }
        guard let site = recent.min(by: { $0.value.p.distance(to: pos) < $1.value.p.distance(to: pos) }),
              let pl = sv.place(site.key) ?? sv.nearest(to: site.value.p, within: 40 * config.scale) else { return false }
        return startErrand(.mealSite, at: pl)
    }

    /// Round its favourite places — its bed, its lookout, the water — by
    /// the ways it knows between them.
    private func goRound() -> Bool {
        guard let sv = places(), let know = knowledge else { return false }
        var stops: [HabitatPlace] = []
        for use in [PlaceUse.sleep, .rest, .lookout, .drink, .perch, .bask] {
            guard let f = know.favourite(for: use, where: { sv.place($0) != nil }), let pl = sv.place(f.key),
                  !stops.contains(where: { $0.point.distance(to: pl.point) < 60 * config.scale }) else { continue }
            stops.append(pl)
        }
        guard stops.count >= 2 else { return false }
        var order: [HabitatPlace] = []
        var from = pos
        while !stops.isEmpty, order.count < 3 {
            let k = stops.indices.min { stops[$0].point.distance(to: from) < stops[$1].point.distance(to: from) }!
            order.append(stops.remove(at: k))
            from = order.last!.point
        }
        return startErrand(.round, at: order[0], then: Array(order.dropFirst()))
    }

    /// Rings on the water where it touches it, or drinks.
    private func ripple(at p: V2, size: CGFloat) {
        guard drops.count < 26 else { return }
        drops.append(Drop(p: p, v: .zero, r: size, kind: .ring, life: randRange(0.9, 1.3), floor: nil, spread: 2.6))
    }

    /// Tools only: what it is off doing in its tank.
    var debugErrand: String {
        guard let e = errand else { return "-" }
        return String(format: "%@ %@ step %d at %@ (%.0f,%.0f)%@", e.kind.rawValue, e.stage.rawValue, e.step, e.place.key,
                      Double(e.place.point.x), Double(e.place.point.y), e.hurry ? " hurry" : "")
    }
    var debugErrandKind: String? { errand?.kind.rawValue }
    var debugErrandPlace: HabitatPlace? { errand?.place }
    var debugUrges: (thirst: CGFloat, view: CGFloat, rest: CGFloat, roam: CGFloat) { (urges.thirst, urges.view, urges.rest, urges.roam) }
    var debugDrinking: Bool { activity == .drink }
    var debugSipAt: V2? { activity == .drink ? sipAt : nil }
    var debugPlaces: PlaceSurvey? { places() }
    /// Tools only: where it would go for `use` just now.
    func debugChoose(_ use: PlaceUse, threat: V2? = nil) -> HabitatPlace? { choose(use, threat: threat) }
    /// Tools only: off to `pl` to look round there (as when exploring).
    @discardableResult
    func debugGo(to pl: HabitatPlace) -> Bool { startErrand(.explore, at: pl, within: 12 * config.scale) }
    /// Tools only: which way along its surface it is going (+1, -1).
    var debugWalkDir: CGFloat { walkDir }
    /// Tools only: set its urges.
    func debugSetUrges(thirst: CGFloat? = nil, view: CGFloat? = nil, rest: CGFloat? = nil, roam: CGFloat? = nil) {
        wakeUrges()
        if let thirst { urges.thirst = thirst }
        if let view { urges.view = view }
        if let rest { urges.rest = rest }
        if let roam { urges.roam = roam }
    }
    /// Tools only: its favourite places and things, as it would choose them.
    var debugFavourites: [String: String] {
        guard let know = knowledge, let tank else { return [:] }
        var out: [String: String] = [:]
        for use in PlaceUse.allCases {
            if let f = know.favourite(for: use, where: { _ in true }) {
                out[use.rawValue] = String(format: "%@ (%.0f,%.0f) %.2f", f.key, Double(f.record.x), Double(f.record.y), Double(f.record.fond(use)))
            }
        }
        let groups: [(String, (HabitatItem) -> Bool)] = [
            ("branch", { $0.kind.definition.group == .branches }),
            ("plant", { $0.kind.definition.shelf == .plants }),
            ("thing", { _ in true }),
        ]
        for (name, f) in groups {
            if let u = know.favouriteThing(among: tank.items.filter(f).map(\.uid)), let it = tank.item(uid: u) { out[name] = "\(it.kind.rawValue) #\(it.id)" }
        }
        return out
    }

    // MARK: The tank alive
    //
    // Its tank as a living place (HabitatEcology.swift): the weather on its
    // things, and the creatures that come to them.
    //
    // Out in the rain it feels it getting to it — sooner the harder it comes
    // down, the stormier, and the timider it is — and doesn't wait for a
    // soaking: off to cover it knows (the house first). There it waits it
    // out, and stays a while after, the timid and the lazy the longer; then
    // a look out, a look at the sky, and out into the open again. Rain left
    // beaded on the leaves catches its eye: over to a drop, a touch of it
    // (the curious), and a drink of it. In a hot sun it basks — on stone
    // warmed through, most of all — until it has had enough, and then into
    // the shade. In a gale it keeps off what sways in it, and gets down off
    // it. The bold and the curious go up somewhere open to watch a mild
    // weather come over. And it hunts by where things are: it knows where
    // prey comes (flowers, water, the litter), and pokes about under bark
    // and in the litter for what may be lying low there. Gone a long while
    // without, it is off to do it sooner and waits longer at it, sleeps
    // less, and misses less of what moves.
    //
    // None of it is a need, and none of it is shown: there is only what it
    // does. Full up, it lets what wanders in be, and watches it instead.

    /// The tank as a living place, handed over with the tank. Nil — the
    /// desktop, the tools unless they give it one — and none of this applies.
    var ecology: HabitatEcology?
    /// In its tank with a mind of its own, and the tank alive.
    private var eco: HabitatEcology? { placesOn ? ecology : nil }
    /// How much the weather out here is getting to it, 0…1.5 (see the top).
    private var weatherWorry: CGFloat = 0
    /// Whether it is getting worse: how the wet was a moment ago, and how
    /// fast it has been rising.
    private var rainWas: CGFloat = 0
    private var rainRising: CGFloat = 0
    /// Out in a hot sun, all told (seconds, about).
    private var sunOn: CGFloat = 0
    /// Last caught sight of a drop on a leaf, went out from cover, poked about.
    private var lastDropSeen: CGFloat = -9999
    /// Things it found no way onto to drink the rain off, and till when it
    /// lets them be.
    private var noWayToDrops: [Int: CGFloat] = [:]
    private var emergedAt: CGFloat = -9999
    /// The drop of rain it is drinking (`Droplet.id`).
    private var sipDrop: Int?
    /// The rain over with it under cover, but not sitting it out on purpose
    /// (a meal in between, say): out it comes all the same, then.
    private var emergeDue: CGFloat?
    private var wasRough = false

    /// Had enough of the weather out here: in, before it is soaked.
    private var worried: Bool { eco != nil && weatherWorry > lerp(0.3, 1.0, personality.bravery) }

    /// How long it has gone without, in its tank alive, 0…1: nothing until
    /// what it last ate is mostly gone (`fed` under 0.3), all of it with
    /// nothing in it. Only ever in what it does (see the top); 0 elsewhere.
    private var hunger: CGFloat { eco == nil ? 0 : clamp((0.3 - fed) / 0.3, 0, 1) }

    /// On something that sways, in a gale out in the open.
    private var shakenByGale: Bool {
        guard mode == .attached, abs(weather.wind) > 0.75, !sheltered, let id = map.owner(of: anchor) else { return false }
        return tank?.item(id: id)?.kind.sways == true
    }

    /// Every frame in the tank: the weather getting to it, the sun on it,
    /// the drop it is drinking going down.
    private func liveEcology(dt: CGFloat) {
        guard let eco else {
            weatherWorry = 0
            sunOn = 0
            return
        }
        let w = weather, P = personality
        let wetNow = max(w.rain, w.snow * 0.7, w.hail * 1.5)
        rainRising = approach(rainRising, (wetNow - rainWas) / max(dt, 1e-3), 0.8, dt)
        rainWas = wetNow
        let rough = wetNow + w.storm * 0.6
        if mode == .attached, !sheltered, rough > 0.04 {
            // (Storms, and hail, the timid can't abide.)
            let dislike = lerp(1.8, 0.45, P.bravery) * (w.storm > 0.3 || w.hail > 0.1 ? 1.7 : 1)
            weatherWorry = min(1.5, weatherWorry + rough * dislike * dt / 5 * (rainRising > 0.002 ? 1.5 : 1))
        } else {
            weatherWorry = max(0, weatherWorry - dt / (sheltered ? 10 : 30))
        }
        let sun = mode == .attached && !sheltered ? w.sun : 0
        if sun > 0.3 { sunOn += dt * (sun + w.heat * 0.5) } else { sunOn = max(0, sunOn - dt * 2) }
        if activity == .drink, let id = sipDrop, activityTime > 0.6 { eco.sip(id, by: dt * 0.3) }
        // Over, with it in under something but not sitting it out on purpose:
        // out in its own time (see `startTankGoal`).
        if w.rough {
            emergeDue = nil
            wasRough = true
        } else if wasRough, w.rain < 0.08, w.snow < 0.1 {
            wasRough = false
            if sheltered, errand?.kind != .shelter {
                emergeDue = t + randRange(6, 16) * lerp(2.6, 0.55, P.bravery) * lerp(0.8, 1.5, P.laziness)
            }
        }
    }

    /// A few times a second in the tank: a drop of rain on a leaf just by it
    /// catches its eye — the curious go over for a closer look, and a drink.
    private func ecologyTick(_ tick: CGFloat) {
        guard let eco, mode == .attached, !isHeld, !eco.droplets.isEmpty, t - lastDropSeen > 14, weather.rain < 0.12 else { return }
        guard caught == nil, huntTarget == nil, inquiry == nil, riding == nil, alertness >= 0.6,
              [.walk, .sneak, .idle, .look, .glance, .groom, .fidget, .peer].contains(activity) else { return }
        if let e = errand, !e.kind.yields || e.kind == .emerge || e.stage == .act { return }
        let sc = config.scale
        // (A glint of water on a leaf: seen from a little way off, up on the
        // leaves over it too.)
        guard let d = eco.droplet(near: pos, within: 140 * sc), (noWayToDrops[d.thing] ?? -1) < t else { return }
        lastDropSeen = t
        look(at: d.p, for: 1.4)
        let P = personality
        if chance(lerp(0.2, 0.85, P.curiosity) * (urges.thirst > 0.3 ? 1.3 : 1)) {
            _ = goForDrop(d)
        } else if [.idle, .look].contains(activity) {
            beginActivity(.look, dur: randRange(0.8, 1.4))
        }
    }

    /// What the weather has it do in its tank, if anything: in before it is
    /// soaked, off something swaying in a gale, into the shade after long in
    /// a hot sun. True if it did something.
    private func ecoWeather() -> Bool {
        guard mode == .attached else { return false }
        let P = personality
        if worried, !sheltered, errand?.kind != .shelter {
            if seekShelter() {
                debugPlaceNote = String(format: "had enough of it (%.2f): in", Double(weatherWorry))
                if emote == .none, chance(0.5) { think(weatherThought() ?? .rain, for: 2.2) }
                return true
            }
        }
        if shakenByGale {
            // Holding on, then down off it and in somewhere steady.
            if activity != .brace, chance(0.5) {
                beginActivity(.brace, dur: randRange(1.0, 1.8))
                return true
            }
            if seekShelter() { return true }
        }
        // Long enough out in a hot sun: the shade (cooler there) — the lazy
        // bask the longest, and the hotter it is the sooner.
        let enough = lerp(35, 130, P.laziness) * (1.2 - 0.5 * weather.heat)
        if weather.sun > 0.45 || weather.heat > 0.5, !sheltered, sunOn > enough, goToShade() { return true }
        // Sun out, and stone it knows warmed through by it: over to bask on it.
        if weather.sun > 0.45, !sheltered, sunOn < enough * 0.6, t - (lastErrand[.bask] ?? -9999) > 60, eco?.warmth.values.contains(where: { $0 > 0.35 }) == true,
           chance(0.35 * lerp(0.6, 1.5, P.laziness)), goFor(.bask) {
            return true
        }
        return false
    }

    /// What it might feel like doing in its tank, alive (see `startTankGoal`).
    private func ecoWants(_ eco: HabitatEcology, into wants: inout [(CGFloat, () -> Bool)]) {
        let P = personality, w = weather, u = urges
        func since(_ k: ErrandKind) -> CGFloat { t - (lastErrand[k] ?? -9999) }
        // Rain left on the leaves: a drop to drink, the curious the likelier.
        if w.rain < 0.1, since(.dew) > 45, let d = nearestDrop(eco) {
            wants.append(((0.35 + u.thirst) * lerp(0.6, 1.5, P.curiosity) * (eco.sinceRain < 300 ? 2 : 1), { self.goForDrop(d) }))
        }
        // A mild weather coming over: the bold and curious go up somewhere
        // open to watch it.
        let mild = !w.isCalm && !w.rough && (w.rain > 0.02 || w.snow > 0.03 || w.fog > 0.2 || abs(w.wind) > 0.25 || w.cold > 0.05)
        if mild, !worried, since(.lookout) > 90 {
            let keen = max(0, P.bravery + P.curiosity - 0.9)
            if keen > 0 { wants.append((1.2 * keen, { self.goFor(.lookout) })) }
        }
        // Hungry: a poke about where something may be lying low — at once,
        // where it saw something go to ground.
        let lying = prey.contains { $0.state == .loose && $0.hidden && $0.noticed }
        let hungry = hunger
        if lying || (fed < 0.6 && since(.forage) > lerp(150, 60, hungry)) {
            wants.append(((lying ? 2.5 : 0.55 * (1 - fed) * (1 + 1.5 * hungry)) * lerp(0.6, 1.4, P.curiosity), { self.goForage() }))
        }
        // Stone warm from the sun, out there: somewhere to bask (the lazy most).
        if !w.rough, eco.warmth.values.contains(where: { $0 > 0.35 }), since(.bask) > 120 {
            wants.append((0.5 * lerp(0.5, 1.6, P.laziness), { self.goFor(.bask) }))
        }
    }

    /// The nearest drop of rain it could get to, not too far off — and
    /// somewhere to stand by it to drink it (see `goForDrop`).
    private func nearestDrop(_ eco: HabitatEcology) -> Droplet? {
        guard let tank, let know = knowledge else { return nil }
        let sc = config.scale
        return eco.droplets.filter { d in
            d.reachable && d.r > 0.9 && d.p.distance(to: pos) < 900 * sc && (noWayToDrops[d.thing] ?? -1) < t
                && tank.item(id: d.thing).map { know.stage(of: $0.uid) != .unknown } ?? false
        }.sorted { $0.p.distance(to: pos) < $1.p.distance(to: pos) }
            .first { eco.spot(near: $0.p + V2(0, map.standoff), within: 34 * sc) != nil }
    }

    /// Over to a drop of rain on a leaf, to drink it.
    @discardableResult
    private func goForDrop(_ d: Droplet) -> Bool {
        guard let eco else { return false }
        let sc = config.scale
        // (Stood on what it is on, just short of it, head to it.)
        guard let s = eco.spot(near: d.p + V2(0, map.standoff), within: 34 * sc) else { return false }
        var pl = HabitatPlace(key: "\(uid(of: d.thing) ?? "tank"):dew", kind: nil, anchor: s.anchor, point: s.point, facing: s.facing,
                              owner: s.owner, thing: d.thing)
        pl.focus = d.p
        pl.along = (d.p - s.point).dot(map.seg(s.anchor)?.dir ?? V2(1, 0)) >= 0 ? 1 : -1
        return startErrand(.dew, at: pl, within: 13 * sc, drop: d.id)
    }

    /// Out from under cover, the rain over: out into the open, a little way
    /// — somewhere it can walk out to; or, with nowhere like that, a look
    /// round from where it is.
    private func goEmerge(from shelter: HabitatPlace) -> Bool {
        guard let sv = places(), mode == .attached else { return false }
        let sc = config.scale
        let here = anchor.loopID
        let open = sv.places.filter {
            $0.standing && $0.q[.exposure] > 0.6 && $0.q[.cover] < 0.3 && $0.q[.access] > 0.5
                && (60 * sc ... 260 * sc).contains($0.point.distance(to: shelter.point))
                && ($0.anchor.loopID == here || canGet(to: $0.anchor))
        }
        emergedAt = t
        if let pl = open.sorted(by: { $0.point.distance(to: pos) < $1.point.distance(to: pos) }).prefix(4).randomElement() {
            return startErrand(.emerge, at: pl, within: 12 * sc)
        }
        guard let seg = map.seg(anchor) else { return false }
        let spot = HabitatPlace(key: shelter.key, kind: nil, anchor: anchor, point: pos, facing: seg.facing, owner: map.owner(of: anchor) ?? 0, thing: 0)
        return startErrand(.emerge, at: spot, within: 30 * sc)
    }

    /// Out of a hot sun, into the shade a while.
    private func goToShade() -> Bool {
        guard let pl = choose(.rest, only: { $0.q[.cover] >= 0.45 && !$0.hanging }) else { return false }
        sunOn = 0
        return startErrand(.shade, at: pl)
    }

    /// Somewhere something may be lying low — where it saw something go to
    /// ground, first; else under bark, in the litter, in the dark, by what
    /// it knows of them — to poke about there.
    private func goForage() -> Bool {
        guard let eco, let tank, let know = knowledge else { return false }
        let sc = config.scale
        let options = eco.hidingPlaces(near: pos, within: 1100 * sc).filter { o in
            let th = eco.sites[o.site].thing
            return th <= 0 || tank.item(id: th).map { know.stage(of: $0.uid) != .unknown } ?? false
        }
        guard !options.isEmpty else { return false }
        var pick = options[0]
        if let p = prey.first(where: { $0.state == .loose && $0.hidden && $0.noticed }),
           let o = options.min(by: { $0.probe.distance(to: p.pos) < $1.probe.distance(to: p.pos) }), o.probe.distance(to: p.pos) < 140 * sc {
            pick = o
        } else {
            // (The likeliest few, and where it has done well before.)
            let few = Array(options.prefix(5))
            let weights = few.map { o -> CGFloat in
                let r = places()?.nearest(to: o.stand.point, within: 40 * sc).flatMap { know.record($0.key) }
                return 1 + (r?.catches ?? 0) * 0.8 + (r?.sightings ?? 0) * 0.4
            }
            var r = randRange(0, weights.reduce(0, +))
            for (o, wt) in zip(few, weights) {
                r -= wt
                if r <= 0 { pick = o; break }
            }
        }
        let th = eco.sites[pick.site].thing
        let key = th > 0 ? "\(uid(of: th) ?? "tank"):forage" : "tank:forage:\(Int(pick.probe.x / 64))"
        var pl = HabitatPlace(key: key, kind: nil, anchor: pick.stand.anchor, point: pick.stand.point, facing: pick.stand.facing,
                              owner: pick.stand.owner, thing: max(th, 0))
        pl.focus = pick.probe
        pl.along = (pick.probe - pick.stand.point).dot(map.seg(pick.stand.anchor)?.dir ?? V2(1, 0)) >= 0 ? 1 : -1
        return startErrand(.forage, at: pl, within: 8 * sc, probe: pick.probe)
    }

    /// What it does at the end of an errand of the tank alive, a step at a time.
    private func actAlive(_ e: inout Errand) -> Bool {
        let sc = config.scale, P = personality
        switch e.kind {
        case .emerge:
            // Out: a look round, and up at the sky; wet, a shake — and a drop
            // of rain on a leaf nearby catches its eye.
            switch e.step {
            case 0:
                e.step = 1
                skyLook(randRange(1.2, 2.2))
                beginActivity(.look, dur: randRange(1.2, 2.2))
            case 1:
                e.step = 2
                if wet > 0.3, t - lastShakeOff > 6 {
                    beginActivity(.shake, dur: 0.7)
                    return true
                }
                return actAlive(&e)
            default:
                if let eco, let d = nearestDrop(eco), d.p.distance(to: pos) < 460 * sc,
                   chance(lerp(0.45, 0.95, P.curiosity) * (urges.thirst > 0.3 ? 1.2 : 1) / (1 + d.p.distance(to: pos) / (600 * sc))) {
                    chainNext = { self.goForDrop(d) }
                }
                return false
            }

        case .forage:
            // A look in under it, eyes low; a front leg in there, feeling
            // about — whatever is lying low there is turned out — and a
            // last look.
            let f = e.probe ?? e.place.focus ?? ahead(of: e.place)
            switch e.step {
            case 0:
                e.step = 1
                look(at: f, for: 3)
                faceThen(f, .peer, for: randRange(1.0, 1.8))
            case 1:
                e.step = 2
                feelAt = pos + (f - pos).clampedLength(30 * sc)
                feelNormal = V2(0, 1)
                look(at: f, for: 2.5)
                beginActivity(.feel, dur: randRange(1.2, 2.0))
                for p in prey where p.state == .loose && (p.hidden || p.sheltering) && p.pos.distance(to: f) < 80 * sc {
                    p.probed(from: pos, map: map)
                    if !p.noticed {
                        p.noticed = true
                        memory?.meet(p.kind.memoryName)
                    }
                    setEmote(.exclaim, 0.8)
                    decisionIn = 0.3
                }
            case 2:
                e.step = 3
                feelAt = nil
                look(at: f, for: 2)
                beginActivity(chance(0.4) ? .peer : .look, dur: randRange(0.8, 1.6))
            default:
                return false
            }

        default:
            return false
        }
        return true
    }

    /// Over to where it went to ground, and a front leg in under there to
    /// turn it out.
    private func probe(for p: Prey, eco: HabitatEcology) {
        let sc = config.scale
        if pos.distance(to: p.pos) < 36 * sc {
            feelAt = pos + (p.pos - pos).clampedLength(30 * sc)
            feelNormal = V2(0, 1)
            look(at: p.pos, for: 2)
            faceThen(p.pos, .feel, for: randRange(0.9, 1.4))
            p.probed(from: pos, map: map)
            return
        }
        if let s = eco.spot(near: p.pos + V2(0, map.standoff), within: 70 * sc) {
            switch headFor(s.anchor, style: .sneak, within: 22 * sc) {
            case .going:
                return
            case .noWay where inHabitat && !map.loops.isEmpty:
                // (No way to it from here: it lets it be a while.)
                huntIgnore[p.id] = t + 30
                huntTarget = nil
                decisionIn = 0.2
                return
            default:
                break
            }
        }
        walkToward(p.pos)
    }

    /// Where what is left of a meal lies: on what it is standing on, just
    /// ahead of it; else down on whatever is under it.
    private func remainsSpot(under p: V2) -> V2? {
        let sc = config.scale
        if mode == .attached, surfaceNormal.y > 0.6, let seg = map.seg(anchor) {
            return anchorPos - surfaceNormal * map.standoff + seg.dir * walkDir * 10 * sc
        }
        return HabitatItem.floor(below: p, on: map, notOwnedBy: -1).map { $0.point - V2(0, map.standoff) }
    }

    /// Something finding its own way into the tank (see
    /// `HabitatEcology.arrival`): on the wing down to what drew it, or out
    /// from under bark, out of the litter, out of the dark. It has to be
    /// noticed before it is hunted, and it goes again after a while.
    @discardableResult
    func releaseInTank(_ a: EcoArrival) -> [Prey] {
        guard !inCinema, inHabitat else { return [] }
        var out: [Prey] = []
        func make(at p: V2) -> Prey {
            let c = Prey(kind: a.kind, id: nextPreyID, at: p, scale: config.scale)
            nextPreyID += 1
            c.wild = true
            c.noticed = false
            c.leaveAge = randRange(150, 330)
            c.home = a.patch
            c.eco = ecology
            out.append(c)
            return c
        }
        if a.kind.flies {
            make(at: a.at).comeIn(landing: a.land?.anchor, map: map)
        } else if let an = a.anchor, let seg = map.seg(an) {
            for i in 0..<a.count {
                var at = an
                at.t = clamp(an.t - a.dir * CGFloat(i) * 22 * config.scale, 4, max(seg.len - 4, 4))
                let c = make(at: a.at)
                c.emerge(on: at, dir: a.dir, map: map)
                c.den = an
            }
        } else {
            return []
        }
        prey += out
        return out
    }

    /// Tools only: how it is in its tank alive.
    var debugEcology: String {
        String(format: "worry %.2f%@ sun %.0fs rising %.3f%@", Double(weatherWorry), worried ? " (worried)" : "", Double(sunOn), Double(rainRising),
               sipDrop != nil ? " sipping a drop" : "")
    }
    var debugWorry: CGFloat { weatherWorry }
    var debugFed: CGFloat { get { fed } set { fed = newValue } }
    var debugHuntTarget: Int? { huntTarget }
    /// Tools only: how its last errand came to an end.
    private(set) var debugErrandEnd = ""
    var debugSunOn: CGFloat { sunOn }
    var debugDropID: Int? { errand?.drop }

    // MARK: First entrance

    /// Its very first arrival, at the end of the welcome: made an occasion
    /// of. It starts out of sight, up behind the menu bar under its icon
    /// (which the app gives a wiggle, as if something were stirring in
    /// there); lets itself down until its head and front legs poke out from
    /// under the bar, and has a look round; ducks back up a touch, shy of
    /// the big wide screen; then comes on down, slow and grand, in front of
    /// whatever is there, bobs on the end of its line and says hello; and
    /// works up a swing and lets go — from then on it is its own spider.
    /// The line is never seen coming from nowhere: the top of it is behind
    /// the menu bar the whole time.
    private struct Entrance {
        enum Phase { case stir, peek, look, shy, drop, hello }
        var phase: Phase = .stir
        /// Time in this phase.
        var t: CGFloat = 0
        /// The bottom of the menu bar, and how far below it it comes down.
        let barY: CGFloat
        let depth: CGFloat
        /// How fast it pays out line (or hauls it in) just now, in screen
        /// points a second whatever its size.
        var pace: CGFloat = 0
        /// Its line's length as it ducked back.
        var shyFrom: CGFloat = 0
        var greeted = false
    }
    private var entrance: Entrance?
    /// Making its first entrance: kept under the menu bar (so it comes out
    /// from behind it), and nothing but the entrance going on.
    var makingEntrance: Bool { entrance != nil }
    /// How long the entrance waits, out of sight, before it shows itself:
    /// the icon's wiggle.
    static let entranceStir: CGFloat = 1.4

    /// `x` is under its menu bar icon; `barY` the bottom of the menu bar,
    /// `top` the top of the screen.
    func makeEntrance(x: CGFloat, barY: CGFloat, top: CGFloat, floorY: CGFloat) {
        teleport(to: V2(x, barY + 200))
        emote = .none
        startled.reset(0)
        wake()
        // Head down, fastened well up out of sight behind the bar: a line
        // fastened any lower would leave no room to hang all of it hidden.
        vel = .zero
        heading = -.pi / 2 + (facing < 0 ? .pi : 0)
        headingTarget = heading
        headingVel = 0
        yaw = facing
        let s = config.scale
        // All of it — the whole of the sprite, head and dangling legs —
        // just clear of the bottom of the bar, its spinnerets under the icon.
        pos = V2(x, barY + (SpiderRenderer.drawRadius + 4) * s)
        pos.x += x - toWorld(spinnerets).x
        let spin = toWorld(spinnerets)
        attachWeb(at: V2(x, max(top + 20 * s, spin.y + 28)))
        // Hung from the menu bar, which is in front of every window: none
        // of them can come over its line.
        webFromDepth = Int.min
        webStyle = .hang
        webLenTarget = webLen
        bungee.reset(0)
        prevHangLen = webLen
        legFramePos = pos
        legFrameHeading = heading
        kneeShape = []
        footWorld = []
        webPlan = []
        decisionIn = 99
        let room = barY - floorY
        entrance = Entrance(barY: barY, depth: clamp(room * 0.36, 160 * s, max(160 * s, room - 120 * s)))
    }

    /// The lowest bit of it drawn: its head, or a dangling foot.
    private var lowestPoint: CGFloat {
        let h = SpiderRenderer.head(for: look)
        var y = toWorld(h.c).y - h.r * config.scale
        for f in footWorld { y = min(y, f.y) }
        return y
    }

    /// Runs the entrance, a frame at a time, while it hangs.
    private func updateEntrance(dt: CGFloat) {
        guard var e = entrance else { return }
        e.t += dt
        let s = config.scale
        // (Plan lengths here are as it hangs from its spinnerets; it hangs
        // head down throughout, so `lineRef` is nothing.)
        switch e.phase {
        case .stir:
            webLenTarget = webLen
            if e.t > Spider.entranceStir { e.phase = .peek; e.t = 0 }
        case .peek:
            // Slowly, until its head and front legs are out.
            e.pace = 34
            webLenTarget = webLen + 30
            if lowestPoint < e.barY - 15 * s {
                webLenTarget = webLen
                e.phase = .look
                e.t = 0
                bungee.velocity = 40
            }
        case .look:
            // A look round from under the bar.
            webLenTarget = webLen
            if e.t > 1.3 {
                e.phase = .shy
                e.t = 0
                e.shyFrom = webLen
                startled.velocity = 5
            }
        case .shy:
            // Oh — all that screen. Back up a touch, a moment, and then
            // it makes up its mind.
            e.pace = 70
            webLenTarget = e.shyFrom - 9 * s
            if e.t > 0.85 {
                e.phase = .drop
                e.t = 0
                happy.velocity = 4
            }
        case .drop:
            // Down, in front of whatever is there, easing in at the end.
            e.pace = 120
            // Out from under the bar for good: fastened now to the bottom
            // of it, where the line comes out, so the rest of its time on
            // this line is on an ordinary line from the menu bar.
            if webAnchor.y > e.barY { refasten(atY: e.barY) }
            webLenTarget = webAnchor.y - e.barY + e.depth
            if abs(webLen - webLenTarget) < 3 {
                e.phase = .hello
                e.t = 0
                bungee.velocity = 210
                happy.velocity = 7
                setEmote(.sparkle, 1.3)
            }
        case .hello:
            webLenTarget = webLen
            if !e.greeted, e.t > 1.1 {
                // Hello! A kick of the legs and a bounce on the line.
                e.greeted = true
                lineJoyUntil = t + 1.6
                bungee.velocity = 150
                happy.velocity = 10
                setEmote(.hearts, 1.4)
            }
            if e.t > 3.2 {
                // And off it goes, with a flourish: a swing, and let go.
                if webAnchor.y > e.barY { refasten(atY: e.barY) }
                entrance = nil
                webPlan = [webLen > 120 * s ? .swing : .toFloor]
                decisionIn = 0
                return
            }
        }
        entrance = e
    }

    /// Fastens the line where it crosses `y` above it, keeping the body
    /// exactly where it is.
    private func refasten(atY y: CGFloat) {
        let dir = V2(sin(webAngle), -cos(webAngle))
        guard dir.y < -0.3, webAnchor.y > y else { return }
        let k = (webAnchor.y - y) / -dir.y
        guard k < webLen - 30 else { return }
        webAnchor += dir * k
        webLen -= k
        webLenTarget -= k
        prevHangLen -= k
        rope.clear()
    }

    /// Decide again soon: something about the world just changed.
    func nudgeDecision() {
        if mode == .attached { queued = nil; decisionIn = min(decisionIn, 0.3) }
        wake()
    }

    /// A map to switch to the moment it leaves its surface — mid-leap or
    /// on a line — so it can jump or climb straight into the habitat.
    private var pendingMap: (map: SurfaceMap, habitat: Bool)?
    /// Called the moment a pending map switch happens.
    var onMapSwitched: (() -> Void)?
    /// While a window it may be walking under is only glass (the tank),
    /// being "covered" by it is nothing to flee from.
    var calmUnderCover = false
    func switchMapOnLeaving(_ newMap: SurfaceMap, habitat: Bool) { pendingMap = (newMap, habitat) }
    private func applyPendingMap() {
        guard let pm = pendingMap else { return }
        pendingMap = nil
        moveInMidAir(map: pm.map, habitat: pm.habitat)
        onMapSwitched?()
    }

    /// Changes map keeping whatever it is doing in the air or on a line.
    func moveInMidAir(map newMap: SurfaceMap, habitat: Bool) {
        map = newMap
        inHabitat = habitat
        prey = []
        caught = nil
        huntTarget = nil
        laser = nil
        peek = nil
        homing = nil
        landing = nil
        launchLoop = ""
        decisionIn = randRange(0.4, 1.0)
    }

    /// Leaps at `point` (which may be on another map: see
    /// `switchMapOnLeaving`) if it can reach it from here.
    /// `throughGlass` lets it leap straight through the surface it is on —
    /// the tank's wall or lid is only glass.
    private var glassLeap = false
    @discardableResult
    func leapIn(to point: V2, throughGlass: Bool = false) -> Bool {
        guard mode == .attached, let launch = ballistic(from: pos, to: point),
              throughGlass || launch.normalized.dot(surfaceNormal) > -0.15 else { return false }
        wake()
        queued = nil
        huntTarget = nil
        glassLeap = throughGlass
        startJump(to: point)
        return true
    }

    /// Tools and the app: what it is standing on, and whether it is in the air.
    var currentLoopID: String? { mode == .attached ? anchor.loopID : nil }
    /// Gathering itself for a leap, or firing a line: about to leave.
    var isLeavingSurface: Bool { mode == .attached && (activity == .crouch || activity == .shoot || (activity == .turn && pendingJump != nil)) }
    var isAirborne: Bool { mode == .airborne }
    /// On its feet on something.
    var isStanding: Bool { mode == .attached }
    var isOnLine: Bool { mode == .dangling }

    /// Lets go of its line and drops.
    func letGo() {
        guard mode == .dangling else { return }
        detachWeb(fade: true)
        mode = .airborne
        air = .fall
        airTime = 0
        noAttachFor = 0.05
        launchLoop = ""
        legMode = .free
    }
    var standingNormal: V2 { surfaceNormal }

    /// Changes map without moving: for stepping through the glass into the
    /// habitat at the very spot it reached it. Whatever it was holding on to
    /// outside is let go of; if it was standing on something, it takes hold
    /// of the nearest edge in here, or drops.
    func moveIn(map newMap: SurfaceMap, habitat: Bool) {
        pendingMap = nil
        map = newMap
        inHabitat = habitat
        climbArrival = nil
        prey = []
        caught = nil
        huntTarget = nil
        laser = nil
        peek = nil
        homing = nil
        pendingJump = nil
        landing = nil
        detachWeb(fade: false)
        webAlpha.reset(0)
        rope.clear()
        switch mode {
        case .attached, .dangling, .nesting:
            mode = .attached
            anchorValid = false
            mapChanged()
        default:
            break
        }
        decisionIn = randRange(0.4, 1.0)
    }

    /// Moves it onto another map — the habitat, or back to the desktop —
    /// dropping in at `p`. Everything it *is* comes with it: its design,
    /// how well fed and how happy it is, its thoughts; everything tied to
    /// the old place (the line, prey, a hunt, a game) is left behind.
    func enter(map newMap: SurfaceMap, at p: V2, habitat: Bool) {
        map = newMap
        inHabitat = habitat
        climbArrival = nil
        prey = []
        caught = nil
        huntTarget = nil
        laser = nil
        peek = nil
        teleport(to: p)
        decisionIn = randRange(0.6, 1.2)
    }

    /// Moves it without any fuss (no fall, no startle): the scene it is in
    /// was rescaled and it goes along with the scenery.
    func teleportQuietly(to p: V2) {
        let d = p - pos
        pos = p
        anchorPos += d
        legFramePos = pos
        if let l = laser { laser = l + d }
        if webActive { webAnchor += d; rope.clear() }
        // Whatever is loose in there goes along with the scenery too.
        for p in prey { p.shift(by: d) }
    }

    /// Everything it knows about where things are, `d` further along: for
    /// going in or out through the tank's glass, between the desktop's
    /// points and the habitat's world, where the same spot has different
    /// numbers. Nothing moves on the screen.
    func shiftSpace(by d: V2) {
        pos += d
        anchorPos += d
        legFramePos += d
        if let l = landing { landing = (l.point + d, l.angle, l.dir) }
        draglineCatchY = draglineCatchY.map { $0 + d.y }
        pounceMark = pounceMark.map { $0 + d }
        surfacePrev = surfacePrev.map { $0 + d }
        pendingJump = pendingJump.map { $0 + d }
        toyContactPos = toyContactPos.map { $0 + d }
        shotTarget += d
        footLimitPos += d
        kneeLimitPos += d
        cursor += d
        prevCursor += d
        cursorCentre += d
        cursorStalkLastPos += d
        if let l = laser { laser = l + d }
        if webActive { webAnchor += d; rope.clear() }
        for p in prey { p.shift(by: d) }
    }

    /// The map it is on was rebuilt under it (the habitat window was
    /// resized): back onto the nearest edge, or let go if there is none.
    func mapChanged() {
        guard mode == .attached else { return }
        if let spot = map.nearestSpot(to: pos, within: 90 * config.scale) {
            anchor = spot.anchor
            anchorPos = spot.point
            pos = spot.point
            legFramePos = pos
            for i in legs.indices { legs[i].foot = legs[i].rest; legs[i].footVel = .zero }
        } else {
            detachAndFall()
        }
    }

    /// The surfaces were rebuilt in a different shape under it — a film has
    /// started or finished, so the rim of the screen is a different set of
    /// edges, or the displays were rearranged. It stays exactly where it
    /// is: its anchor is read off the new map from where it is standing,
    /// not carried over by index (an index that meant "the left wall" a
    /// moment ago may mean "the floor" now). A short shift, such as the
    /// menu bar sliding away from under it, it glides across; only if the
    /// ground has really gone — a window now under the video — does it fall.
    func surfacesRestructured() {
        guard mode == .attached else { return }
        // Still standing on the very same line: nothing to do.
        if let p = map.worldPoint(anchor), p.distance(to: anchorPos) < 1 { return }
        guard let spot = map.nearestSpot(to: anchorPos, within: 60 * config.scale) else {
            detachAndFall()
            return
        }
        // Keep walking the same way across the screen, whichever way the
        // new edge happens to run.
        let wasAlong = surfaceNormal.rotated(by: -.pi / 2)
        if spot.seg.dir.dot(wasAlong) < 0 {
            walkDir = -walkDir
            facing = -facing
            pendingDir = -pendingDir
        }
        anchor = spot.anchor
        lastLoopRect = nil
        stuckFor = 0
        anchorValid = true
        anchorGlide = 3
        cinemaSeat = nil
    }

    /// Whether a surface is a ledge on a web page, by its name ("page:…",
    /// as WebPages.swift names them) — gone from the map or not.
    static func isPageLedge(_ loopID: String) -> Bool { loopID.hasPrefix("page:") }

    /// A web page it may be on was read afresh (see WebPages.swift): the
    /// ledge under it found again — a pixel off, a little longer or
    /// shorter, joined round a corner it was not before — or not at all.
    /// It keeps its place on the ground: its anchor is read off the ledge
    /// from where it stands, not carried over by index, and only if there
    /// is nothing there any more does it let go. A ledge found somewhere
    /// else because the whole page moved (`moved`, by name) carries it
    /// along. (A ledge carried along by a scroll, or a window moved, is
    /// not this: it rides those as it goes.)
    func pageLedgesChanged(moved: [String: V2] = [:]) {
        guard mode == .attached, !isHeld, let loop = map.loop(anchor.loopID), loop.kind == .webLedge else { return }
        let stood = anchorPos + (moved[loop.id] ?? .zero)
        if let p = map.worldPoint(anchor), p.distance(to: stood) < 1 { return }
        let near = 10 * config.scale + 4
        var best: (anchor: Anchor, d: CGFloat, seg: Seg)?
        for (i, s) in loop.segs.enumerated() {
            let (t, d) = projectOnSegment(stood, s.a, s.b)
            if d <= near, s.isOpen(at: t), best == nil || d < best!.d { best = (Anchor(loopID: loop.id, segIdx: i, t: t), d, s) }
        }
        if best == nil, let spot = map.nearestSpot(to: stood, within: near) {
            best = (spot.anchor, 0, spot.seg)
        }
        guard let b = best else {
            detachAndFall(lineUp: true)
            return
        }
        let wasAlong = surfaceNormal.rotated(by: -.pi / 2)
        if b.seg.dir.dot(wasAlong) < 0 {
            walkDir = -walkDir
            facing = -facing
            pendingDir = -pendingDir
        }
        anchor = b.anchor
        lastLoopRect = nil
        stuckFor = 0
        anchorValid = true
        // Carried: quickly, as a dragged window carries it.
        anchorGlide = moved[loop.id] == nil ? 8 : 30
    }

    // MARK: Rescue

    /// Puts it in the air at `p`, whatever it was doing, with everything it
    /// was holding on to let go: the line, the hammock, the pointer, the
    /// hunt. It falls from there onto whatever is below, or fires a line.
    func teleport(to p: V2) {
        isHeld = false
        grabOffset = .zero
        detachWeb(fade: false)
        webAlpha.reset(0)
        rope.clear()
        homing = nil
        pendingJump = nil
        huntPounce = false
        pounceMark = nil
        landing = nil
        landingReach = 0
        hurrying = false
        escapeUntil = 0
        occludedFor = 0
        offScreenFor = 0
        if let c = caught {
            // Whatever it was eating comes along and is dropped loose.
            c.state = .loose
            c.eaten = 0
            c.pos = p
            c.drop()
            caught = nil
        }
        queued = nil
        activity = .idle
        activityTime = 0
        sleepiness.reset(0)
        lid.reset(0)
        mode = .airborne
        air = .fall
        pos = p
        vel = V2(0, -10)
        airTime = 0
        noAttachFor = 0.05
        launchLoop = ""
        anchorValid = false
        legMode = .free
        heading = 0
        headingTarget = 0
        headingVel = 0
        yaw = facing
        for i in legs.indices {
            legs[i].foot = legs[i].rest
            legs[i].footVel = .zero
            legs[i].swinging = false
        }
        legFramePos = pos
        legFrameHeading = heading
        decisionIn = randRange(0.5, 1.0)
        setEmote(.surprise, 0.8)
        startled.velocity = 6
    }

    // MARK: Food

    /// Lets something loose on the desktop for it to hunt. Ground creatures
    /// drop in onto a ledge some way off; a fly is let go in the air.
    @discardableResult
    /// `spot`, for the tools only: exactly there instead.
    /// `area`: somewhere in there (the part of the tank the glass shows).
    func release(_ kind: PreyKind, at spot: V2? = nil, in area: CGRect? = nil) -> Prey {
        let screen = area ?? confine ?? map.screenFrame(containing: pos)
        // Near it — or, let loose somewhere it isn't, in the middle of there.
        let near = area.map { $0.contains(pos.point) ? pos : V2($0.midX, $0.minY + $0.height * 0.3) } ?? pos
        var at: V2
        if let spot {
            at = spot
        } else if kind.flies {
            at = V2(clamp(near.x + randRange(-380, 380), screen.minX + 80, screen.maxX - 80),
                    clamp(near.y + randRange(120, 300), screen.minY + 80, screen.maxY - 80))
        } else {
            // A ledge facing up, in the open, a decent distance away.
            var best: (score: CGFloat, point: V2)?
            for spot in map.sampleSpots(spacing: 40) where spot.seg.facing == .up && screen.contains(spot.point.point) {
                let d = spot.point.distance(to: pos)
                guard d > 160, spot.seg.isOpen(at: spot.anchor.t) else { continue }
                let score = remap(d, 160, 700, 1.2, 0.6) * spot.loop.kind.appeal * randRange(0.7, 1.3)
                if best == nil || score > best!.score { best = (score, spot.point) }
            }
            at = best?.point ?? V2(clamp(near.x + randRange(-300, 300), screen.minX + 80, screen.maxX - 80), screen.minY + 60)
            at.y += 30   // dropped in from a little way up
        }
        let p = Prey(kind: kind, id: nextPreyID, at: at, scale: config.scale)
        p.home = confine
        nextPreyID += 1
        prey.append(p)
        memory?.meet(kind.memoryName)
        wake()
        if mode == .attached, [.rest, .sleep, .idle, .look].contains(activity) {
            decisionIn = min(decisionIn, 0.3)
        }
        setEmote(.question, 0.8)
        return p
    }

    /// Something finding its own way in, unasked: through the side of the
    /// screen if it flies, out of a crack somewhere if it walks — ants in a
    /// little line. It has to be noticed before it is hunted, and it goes
    /// again after a while if it is not caught. Nothing, if there is
    /// nowhere for it.
    @discardableResult
    func releaseWild(night: Bool, raining: Bool) -> [Prey] {
        guard !inCinema else { return [] }
        let kind = PreyKind.wanderingIn(night: night, raining: raining)
        let screen = confine ?? map.screenFrame(containing: pos)
        var out: [Prey] = []
        func make(at p: V2) -> Prey {
            let c = Prey(kind: kind, id: nextPreyID, at: p, scale: config.scale)
            nextPreyID += 1
            c.home = confine
            c.wild = true
            c.noticed = false
            c.leaveAge = randRange(100, 240)
            out.append(c)
            return c
        }
        if kind.flies {
            if confine == nil {
                let fromLeft = chance(0.5)
                let p = make(at: V2(fromLeft ? screen.minX - 20 : screen.maxX + 20,
                                    randRange(screen.minY + screen.height * 0.35, screen.maxY - 80)))
                p.vel = V2(fromLeft ? 120 : -120, randRange(-20, 20))
            } else {
                make(at: V2(randRange(screen.minX + 40, screen.maxX - 40), randRange(screen.midY, screen.maxY - 40))).alpha = 0
            }
        } else {
            let spots = map.sampleSpots(spacing: 50).filter {
                ($0.seg.facing == .up || (kind.climbs && $0.seg.facing != .down)) && screen.contains($0.point.point)
                    && $0.point.distance(to: pos) > 260 * config.scale && $0.seg.isOpen(at: $0.anchor.t)
            }
            guard let spot = spots.randomElement() else { return [] }
            let dir: CGFloat = chance(0.5) ? 1 : -1
            for i in 0..<(kind == .ant ? Int.random(in: 2...3) : 1) {
                var a = spot.anchor
                a.t = clamp(a.t - dir * CGFloat(i) * 24 * config.scale, 10, max(spot.seg.len - 10, 10))
                make(at: spot.point).emerge(on: a, dir: dir, map: map)
            }
        }
        prey += out
        return out
    }

    /// Whether anything loose moved this frame.
    var preyAstir: Bool { prey.contains { $0.astir } }

    /// The creature under the pointer, if any, for picking up.
    func preyHit(_ p: V2) -> Prey? {
        prey.first { $0.state == .loose && $0.pos.distance(to: p) < 22 * $0.scale + 6 }
    }

    func beginPreyGrab(_ p: Prey, at point: V2) {
        p.held = true
        p.noticed = true
        p.vel = .zero
        p.pos = point
        lastUserActivity = t
        if huntTarget == p.id { huntSince = t }
    }

    func movePreyGrab(_ p: Prey, to point: V2) {
        p.pos = point
        lastUserActivity = t
    }

    func endPreyGrab(_ p: Prey, throwVelocity v: V2) {
        p.held = false
        p.vel = v.clampedLength(1400)
        p.drop()
        // Fresh interest in it.
        huntTarget = nil
        huntPauseUntil = 0
        if mode == .attached, caught == nil { decisionIn = min(decisionIn, 0.4) }
    }

    /// Force-pressed flat on the pointer. If that was what it was after, the
    /// hunt is off; if it was awake and close enough to see, it jumps.
    func squashPrey(_ p: Prey) {
        guard p.state == .loose else { return }
        p.squashFlat()
        lastUserActivity = t
        if huntTarget == p.id {
            huntTarget = nil
            huntPounce = false
            pounceMark = nil
        }
        if activity != .sleep, !dormant, !inHammock, p.pos.distance(to: pos) < 320 * config.scale {
            setEmote(.surprise, 0.8)
            startled.velocity = 4
        }
    }

    /// Whatever it is after: the nearest thing still loose.
    private func quarry() -> Prey? {
        guard t > huntPauseUntil, !inCinema else { return nil }
        // In its tank with it coming down hard: in out of it first, bar a
        // meal right by it — and sitting it out under cover, only what comes
        // right by it.
        let stormy = eco != nil && (weather.rough || worried)
        let reach: CGFloat = stormy ? (sheltered ? 110 : 150) * config.scale : .greatestFiniteMagnitude
        if let id = huntTarget, let p = prey.first(where: { $0.id == id && $0.state == .loose && !$0.spurned && !$0.gone }) {
            if p.pos.distance(to: pos) < reach, canGet(to: p) { return p }
            huntTarget = nil
        }
        // Only what it has spotted, and not what it knows tastes horrible —
        // nor, in its tank, what is lying low out of sight, nor (full up)
        // what has only wandered in: it lets those be, and watches them.
        let full = eco != nil && fed > lerp(0.7, 0.9, personality.energy)
        // (In its tank, nor what it has no way to get to.)
        let loose = prey.filter {
            $0.state == .loose && $0.noticed && !$0.spurned && $0.alpha > 0.4 && !$0.hidden && !(full && $0.wild)
                && (!stormy || $0.pos.distance(to: pos) < reach)
                && !($0.kind.bitter && (memory?.fondness(of: $0.kind.memoryName) ?? 0) < -0.15)
                && (huntIgnore[$0.id] ?? -1) < t && canGet(to: $0)
        }
        // The nearest — though what it has come to like best looks nearer.
        func far(_ p: Prey) -> CGFloat { p.pos.distance(to: pos) / (1 + 0.5 * max(memory?.fondness(of: p.kind.memoryName) ?? 0, 0)) }
        guard let nearest = loose.min(by: { far($0) < far($1) }) else { return nil }
        huntTarget = nearest.id
        huntSince = t
        return nearest
    }

    private func updatePrey(dt: CGFloat) {
        let onLoop = mode == .attached ? anchor.loopID : nil
        // (In the tank, they know their way about it: see HabitatEcology.swift.)
        let tankEco = inHabitat ? ecology : nil
        for p in prey {
            p.eco = tankEco
            p.update(dt: dt, t: t, map: map, spider: pos, spiderLoop: onLoop, cursor: cursor)
        }
        spotNewcomers(dt: dt)
        // Lying in wait for an ant, or creeping after one: it walks right
        // into its jaws.
        if caught == nil, mode == .attached, pendingJump == nil, [.crouch, .idle, .look, .turn, .sneak, .shake].contains(activity),
           let id = huntTarget, prey.contains(where: { $0.id == id && $0.kind == .ant }) {
            snapAtPrey(reach: 10)
        }
        if let c = caught {
            // Held under the fangs, between the front legs, and turned over
            // as it is eaten.
            let hd = SpiderRenderer.head(for: look)
            let lean = clamp(pitch.value + runNose, -0.6, 0.6)
            let pv = SpiderRenderer.leanPivot
            var m = V2(hd.c.x + hd.r * 0.55, hd.c.y - hd.r * 0.62 - 3 * (1 - c.eaten))
            m = pv + (m - pv).rotated(by: lean) + V2(-lean * 8, lean * 2)
            c.pos = toWorld(m)
            c.heading = heading + sin(t * 9) * 0.15
            c.facing = facing
        }
        prey.removeAll { ($0.state == .eaten && $0.alpha <= 0) || $0.gone }
        // In its tank: something where it has no way to get to it for a good
        // while — shut in, up out of reach — slips away (see `Prey.slipAway`).
        reachCheckIn -= dt
        if reachCheckIn <= 0 {
            let step = 1 - reachCheckIn
            reachCheckIn = 1
            if inHabitat, mode == .attached, !prey.isEmpty, let n = tankNav() {
                let reachable = n.reachable(from: anchor, dir: walkDir)
                for p in prey where p.state == .loose && !p.held {
                    guard let a = p.anchor else { continue }
                    if reachable(a) {
                        p.unreachableFor = 0
                    } else {
                        p.unreachableFor += step
                        if p.unreachableFor > 45 { p.slipAway() }
                    }
                }
            }
            if !huntIgnore.isEmpty { huntIgnore = huntIgnore.filter { $0.value > t } }
        }
        fed = max(0, fed - dt / 900)
        // Lost track of it for too long: leave it be for a while.
        if huntTarget != nil, t - huntSince > 150 {
            huntTarget = nil
            huntPauseUntil = t + 12
        }
    }

    /// Something that wandered in catches its eye: sooner the nearer it is
    /// and if it moves, and hardly at all in its sleep. Then the hunt is on.
    private func spotNewcomers(dt: CGFloat) {
        for p in prey where p.state == .loose && !p.noticed && p.alpha > 0.5 {
            let asleep = activity == .sleep || dormant || inHammock
            // (Hungry in its tank, it is quicker to anything moving.)
            let sight = (asleep ? 90 : 340) * config.scale * (1 + 0.5 * hunger)
            let d = p.pos.distance(to: pos)
            guard d < sight, !inCinema else { continue }
            // (Lying low under bark or in the litter, it is hard to make out.)
            let rate = (p.astir ? 0.9 : 0.2) * remap(d, 0, sight, 3, 0.4) * (asleep ? 0.3 : 1) * (p.hidden ? (1 - p.cover) * 0.25 : 1)
            guard chance(rate * dt) else { continue }
            p.noticed = true
            memory?.meet(p.kind.memoryName)
            if activity == .sleep, mode == .attached { wake() }
            setEmote(.exclaim, 0.9)
            if mode == .attached, caught == nil { decisionIn = min(decisionIn, 0.4) }
        }
    }

    /// The hunt, one decision at a time: close in along its own ledge,
    /// stalking the last stretch, and pounce; or leap to wherever it can get
    /// nearest to; a fly in the air is snatched when it comes within range.
    private func hunt(_ p: Prey) {
        // Gone to ground under something in its tank: over to where it went,
        // and a front leg in under there to turn it out.
        if p.hidden, let eco {
            probe(for: p, eco: eco)
            return
        }
        let d = p.pos - pos
        let dist = d.length
        let sc = config.scale
        // Going nowhere (the way along its edge is blocked, say) — after a
        // few tries it stops walking and leaps instead.
        if pos.distance(to: huntLastPos) < 12 * sc { huntStalls += 1 } else { huntStalls = 0 }
        huntLastPos = pos
        let stalled = huntStalls >= 3
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        let seg = loop.segs[anchor.segIdx]
        let along = d.dot(seg.dir)
        let off = abs(d.dot(seg.normal))
        let facingIt = along * walkDir >= 0
        // A spider sure of itself springs from further off.
        let reach = 75 * sc * (1 + learned.prowess)

        if (p.kind.flies && !p.onSurface) || p.aloft {
            // In the air: snatch it if it comes near enough, otherwise keep
            // under it, watching. A mosquito darts far too fast for that:
            // only while it hangs still, and right where it hangs.
            let snatchable = p.kind != .mosquito || p.hovering
            let lead = p.kind == .mosquito ? p.pos : p.pos + p.vel * 0.22
            if snatchable, dist < 230 * sc, t - lastPounceAt > 1.2, ballistic(from: pos, to: lead) != nil {
                pounce(at: lead)
            } else if abs(along) > 80 {
                turnTo(along >= 0 ? 1 : -1, then: .walk, for: clamp(abs(along) / max(config.walkSpeed, 1), 0.4, 2.0))
            } else {
                beginActivity(.look, dur: randRange(0.5, 1.1))
            }
            return
        }

        // An ant feels it coming and is off, and is too quick to chase down:
        // lie in wait in its path instead, or leap on ahead of it.
        if p.kind == .ant, let pa = p.anchor {
            if dist < 14 * sc { catchPrey(p); return }
            let coming = pa.loopID == anchor.loopID && p.travel.dot(pos - p.pos) > 0 && dist < 450 * sc
            if coming {
                // (It is snapped up as it walks into reach: see `updatePrey`.)
                if !facingIt, abs(along) > 10 {
                    turnTo(along >= 0 ? 1 : -1, then: .crouch, for: randRange(0.4, 0.7))
                } else {
                    beginActivity(.crouch, dur: randRange(0.3, 0.5))
                    pendingJump = nil
                }
                return
            }
            if !stalled, let ahead = spotAhead(of: p) {
                startJump(to: ahead)
                huntStalls = 0
                return
            }
            if p.anchor?.segIdx == anchor.segIdx, pa.loopID == anchor.loopID {
                // Nowhere to get ahead to: creep after it — walking would
                // only give it away.
                let dir: CGFloat = along >= 0 ? 1 : -1
                turnTo(dir, then: .sneak, for: clamp(abs(along) / max(config.walkSpeed * 0.42, 1) * 0.8, 0.4, 3.0))
                return
            }
        }

        // Hanging under something with it on the ground just below: it
        // drops on it from above — no creeping along the underside first.
        // (Gravity does the work: a good deal further down than it could
        // spring along a ledge, not so far out to the side.)
        if seg.normal.y < -0.5, p.onSurface, d.y < -10 * sc, -d.y < 300 * sc, abs(d.x) < reach * 1.4 - d.y * 0.35 {
            let settled = p.vel.length < 20
            let aim = settled ? p.mouthPoint : p.pos + p.vel * 0.3
            if p.tucked {
                // A beetle shut up in its shell: wait above it.
                beginActivity(.crouch, dur: randRange(0.6, 1.0))
                pendingJump = nil
                return
            }
            if t - lastPounceAt > 1.2, let launch = ballistic(from: pos, to: aim), launch.normalized.dot(seg.normal) > -0.15 {
                pounce(at: aim)
                return
            }
        }

        // In its tank: along what it is on to it, if it is on that too; a
        // spring straight onto it, if it has one from here; else its way
        // there (see "Its ways about the tank") — and if there is none, it
        // lets it be for a while.
        if inHabitat, !map.loops.isEmpty, let pa = p.anchor {
            huntInTank(p, pa, dist: dist, reach: reach)
            return
        }

        let sameEdge = p.anchor?.loopID == anchor.loopID && p.anchor?.segIdx == anchor.segIdx
        if sameEdge || (off < 30 * sc && abs(along) < 140 * sc) {
            let settled = p.onSurface && p.vel.length < 20
            if dist < 14 * sc {
                catchPrey(p)
            } else if p.tucked, abs(along) < reach * 1.4 {
                // Shut up in its shell: nothing for it but to keep quite
                // still beside it, and wait for it to come out.
                beginActivity(.crouch, dur: randRange(0.6, 1.0))
                pendingJump = nil
            } else if abs(along) < reach, facingIt, settled, t - lastPounceAt > 1.2 {
                // Close, facing it, and it is sitting still: pounce.
                pounce(at: p.mouthPoint)
            } else if abs(along) < reach, facingIt {
                // It is on the move: wait, poised, for it to settle.
                beginActivity(.crouch, dur: randRange(0.3, 0.6))
                pendingJump = nil
            } else {
                // Close in: a sneak for the last stretch, a walk before that.
                let dir: CGFloat = along >= 0 ? 1 : -1
                // (A beetle shuts up at anything walking at it: creep from further off.)
                let style: Activity = abs(along) < (p.kind.armoured ? 380 : 230) * sc ? .sneak : .walk
                let speed = style == .sneak ? config.walkSpeed * 0.42 : config.walkSpeed
                turnTo(dir, then: style, for: clamp(abs(along) / max(speed, 1) * 0.8, 0.4, 3.0))
            }
            return
        }
        // On the same window or screen, round a corner from it: walk round
        // the short way. That is how it gets from a window's side to its top.
        if !stalled, let pa = p.anchor, pa.loopID == anchor.loopID, pa.segIdx != anchor.segIdx {
            // Round its own window to the prey, whichever way is open and
            // shorter (a window in front can block one way round).
            var way: (d: CGFloat, dir: CGFloat)?
            for dir in [CGFloat(1), -1] {
                if let d = loopDistance(loop, to: pa, dir: dir), way == nil || d < way!.d { way = (d, dir) }
            }
            if let w = way {
                turnTo(w.dir, then: .walk, for: clamp(w.d / max(config.walkSpeed, 1), 1.0, 3.0))
                return
            }
        }
        // Somewhere else: leap to the spot nearest it that it can reach —
        // preferring its own edge, and never through what it stands on.
        var best: (score: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) {
            let dp = spot.point.distance(to: p.pos)
            guard spot.point.distance(to: pos) > 50, dp < dist - 30 else { continue }
            guard let launch = ballistic(from: pos, to: spot.point),
                  launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
            var score = dp
            if spot.loop.id == p.anchor?.loopID { score *= 0.5 }
            if spot.loop.id == anchor.loopID { score *= 1.5 }
            if best == nil || score < best!.score { best = (score, spot.point) }
        }
        if let b = best, stalled || abs(along) < 260 * sc || chance(0.5 + learned.prowess) {
            startJump(to: b.point)
            huntStalls = 0
        } else {
            walkToward(p.pos)
        }
    }

    /// The hunt in its tank, for something on a surface (see `hunt`).
    private func huntInTank(_ p: Prey, _ pa: Anchor, dist: CGFloat, reach: CGFloat) {
        let sc = config.scale
        let settled = p.onSurface && p.vel.length < 20
        if dist < 14 * sc {
            catchPrey(p)
            return
        }
        // On the same surface, not far round it: along it, creeping the last
        // of the way; and a pounce once it is near, facing it, and the thing
        // keeps still — or, where no pounce would get there cleanly, right
        // up to it.
        // (A pounce from right here that came to nothing: not that one again.)
        let refused = t - pounceRefused.at < 4 && pos.distance(to: pounceRefused.from) < 10 * sc
        if pa.loopID == anchor.loopID, let way = loopWay(to: pa), way.dist < 220 * sc {
            // (Right over it, whichever way it faces is facing it.)
            let facing = way.dir == walkDir || way.dist < 6 * sc
            if p.tucked, way.dist < reach * 1.4 {
                // Shut up in its shell: nothing for it but to keep quite
                // still beside it, and wait for it to come out.
                beginActivity(.crouch, dur: randRange(0.6, 1.0))
                pendingJump = nil
                return
            }
            // (Down onto it even from right on top of it: the pounce is a
            // hop along the surface, and it comes down with it pinned.)
            if way.dist < reach, facing, settled, t - lastPounceAt > 1.2, !refused, Spider.arc(from: pos, to: p.mouthPoint) != nil {
                pounce(at: p.mouthPoint)
                return
            }
            if way.dist < reach * 0.8, facing, !settled {
                // It is on the move: wait, poised, for it to settle.
                beginActivity(.crouch, dur: randRange(0.3, 0.6))
                pendingJump = nil
                return
            }
            // (A beetle shuts up at anything walking at it: creep from further off.)
            let style: Activity = way.dist < (p.kind.armoured ? 380 : 230) * sc ? .sneak : .walk
            let speed = style == .sneak ? config.walkSpeed * 0.42 : config.walkSpeed
            walkGoal = (pa, (refused ? 2 : 8) * sc)
            routeHop = nil
            lookAhead(way.dir)
            turnTo(way.dir, then: style, for: clamp(way.dist / max(speed, 1) * 1.3, 0.4, 8))
            debugHuntNote = "along its surface"
            return
        }
        // Near, and a clean spring straight onto it from here.
        if dist < reach * 1.8, settled, !p.tucked, t - lastPounceAt > 1.2, !refused, pounceable(p.mouthPoint) {
            pounce(at: p.mouthPoint)
            debugHuntNote = "spring"
            return
        }
        debugHuntNote = "by its ways"
        switch navGo(to: pa, within: 30 * sc, style: dist < 400 * sc ? .sneak : .walk) ?? .noWay {
        case .going:
            return
        case .there:
            // As near as its ways go, on something right by where it is: a
            // pounce from here (along what it stands on, if need be) — and
            // if that comes to nothing, it lets it be a while.
            if refused {
                huntIgnore[p.id] = t + 20
                huntTarget = nil
                decisionIn = 0.2
            } else if settled, t - lastPounceAt > 1.2, Spider.arc(from: pos, to: p.mouthPoint) != nil {
                pounce(at: p.mouthPoint)
                debugHuntNote = "pounce from by it"
            } else {
                beginActivity(.crouch, dur: randRange(0.4, 0.8))
                pendingJump = nil
            }
        case .noWay:
            // No way to it from here: it lets it be a while.
            huntIgnore[p.id] = t + 30
            huntTarget = nil
            decisionIn = 0.2
            setEmote(.question, 0.8)
        }
    }

    /// A pounce it gathered itself for and then could not make (out of
    /// reach after all, or only through something): when, and from where.
    private var pounceRefused: (at: CGFloat, from: V2) = (-99, .zero)
    /// Tools: how the hunt in its tank went, last it decided.
    private(set) var debugHuntNote = ""

    /// The leap it was gathering itself for is off: if it was a pounce, it
    /// is no longer one (a pounce grabs nothing on the way to its mark: see
    /// `updateAirborne`), and that pounce from here is noted.
    private func calledOffPounce() {
        guard huntPounce else { return }
        huntPounce = false
        pounceMark = nil
        pounceRefused = (t, pos)
    }

    /// A pounce at `point` from here would get there, clean.
    private func pounceable(_ point: V2) -> Bool {
        guard let launch = ballistic(from: pos, to: point) else { return false }
        return launch.normalized.dot(surfaceNormal) > -0.15
    }

    /// On a walk to its prey by its ways: the prey has gone somewhere else
    /// since it planned it, or it is close now — time to decide again.
    private func huntMoved() -> Bool {
        guard let trip = navTrip, let p = prey.first(where: { $0.id == huntTarget }), let a = p.anchor,
              let there = map.worldPoint(a) else { return true }
        return there.distance(to: trip.point) > 40 * config.scale || p.pos.distance(to: pos) < 200 * config.scale
    }

    /// Which way along a loop is the shorter walk to `target`: +1 with the
    /// segments, -1 against. Nil if it is on this very segment.
    private func shortWayRound(_ loop: SurfaceLoop, to target: Anchor) -> CGFloat? {
        guard target.segIdx != anchor.segIdx, target.segIdx < loop.segs.count else { return nil }
        var total: CGFloat = 0
        var starts: [CGFloat] = []
        for seg in loop.segs { starts.append(total); total += seg.len }
        let here = starts[anchor.segIdx] + anchor.t
        let there = starts[target.segIdx] + target.t
        var forward = there - here
        if loop.closed {
            if forward < 0 { forward += total }
            return forward <= total - forward ? 1 : -1
        }
        return forward >= 0 ? 1 : -1
    }

    /// A spot to leap to on the ant's own window, a little way ahead of it
    /// along its path, to wait for it there.
    private func spotAhead(of p: Prey) -> V2? {
        guard let pa = p.anchor else { return nil }
        let sc = config.scale
        let want = p.pos + p.travel * 170 * sc
        var best: (d: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 30) where spot.loop.id == pa.loopID {
            let d = spot.point.distance(to: want)
            guard d < 140 * sc, spot.point.distance(to: pos) > 50, (spot.point - p.pos).dot(p.travel) > 60 * sc,
                  let launch = ballistic(from: pos, to: spot.point), launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
            if best == nil || d < best!.d { best = (d, spot.point) }
        }
        return best?.point
    }

    private func pounce(at point: V2) {
        lastPounceAt = t
        huntPounce = true
        pounceMark = point
        pendingJump = point
        beginActivity(.crouch, dur: randRange(0.28, 0.42))
    }

    private func catchPrey(_ p: Prey) {
        guard p.state == .loose else { return }
        if p.kind.armoured, p.tucked {
            // Fangs on a shell: they skid off it, and the beetle clamps up
            // all the tighter.
            guard p.age - p.lastKnockAge > 1 else { return }
            p.knock()
            huntPounce = false
            remember(.huntMissed, 0.4)
            setEmote(.question, 0.9)
            return
        }
        p.letGo()
        p.state = .caught
        caught = p
        remember(.huntWon)
        noteCatch(at: p.pos)
        huntTarget = nil
        huntPounce = false
        happy.velocity = 6
        setEmote(.sparkle, 0.8)
        if mode == .attached {
            settleToMeal(p)
        }
    }

    /// Anything within reach of the fangs right now?
    private func snapAtPrey(reach: CGFloat) {
        guard caught == nil else { return }
        let hd = SpiderRenderer.head(for: look)
        let mouth = toWorld(V2(hd.c.x + hd.r * 0.55, hd.c.y - hd.r * 0.62))
        for p in prey where p.state == .loose {
            if p.pos.distance(to: mouth) < (p.kind.catchRadius + reach) * config.scale {
                catchPrey(p)
                return
            }
        }
    }

    private func finishMeal() {
        guard let c = caught else { return }
        if c.kind.bitter {
            // Horrible. Out it comes, none the worse for it — and that is a
            // lesson learnt.
            caught = nil
            c.spatOut(map: map, awayFrom: pos)
            memory?.warm(to: c.kind.memoryName, by: -0.4)
            think(.text("Yuck!"), for: 2.4)
            queue(.shake, 0.6)
            // No, no, no — once it has shaken itself off.
            if !Spider.debugNoBodyLanguage { shakeHead(in: 0.6) }
            return
        }
        c.state = .eaten
        c.eaten = 1
        caught = nil
        mealCarry = nil
        // What is left of it is left where it was eaten.
        if leavesTraces, traceOdds(0.85) { traces?.leaveLeftover(of: c.kind, at: c.pos, facing: facing) }
        // (In its tank, for the ants.)
        if let eco, c.kind.leavesRemains, chance(0.85), let at = remainsSpot(under: c.pos) {
            eco.leaveRemains(of: c.kind, at: at, angle: randRange(-0.35, 0.35))
        }
        fed = min(1, fed + c.kind.nourishment)
        remember(.fed)
        memory?.warm(to: c.kind.memoryName, by: 0.15)
        happy.velocity = 9
        setEmote(.hearts, 1.6)
        queue(.wiggle, randRange(0.8, 1.3))
        // That hit the spot: a nod to itself, now and then.
        if !Spider.debugNoBodyLanguage, chance(0.35) { nod(times: 2) }
    }

    // MARK: Toys
    //
    // Toys (see Toys.swift), played with the pointer much as the laser is:
    // while you have one going — dangling, thrown, dropped, wound — it
    // drops what it is doing and goes for it, the playful at once, the lazy
    // in their own time. A timid one gives a new toy a look from a safe
    // distance first, and backs off if it comes at it. Then it plays: bats
    // it along and chases after it, pounces on it, leaps at the feather.
    // Left lying about, a toy still gets played with now and then, as the
    // mood takes it; it tires of it after a while (the playful take longer),
    // though never while you are playing with it.

    /// The toys out on the desktop, shared with any visitors. Only played
    /// with on the desktop they are on, not from inside the habitat.
    var toys: ToyBox?
    private enum ToyStage { case investigate, play, retreat }
    private struct ToyPlay {
        var id: Int
        var stage: ToyStage
        var since: CGFloat
        var stageSince: CGFloat
        /// Seconds spent sizing it up from close by.
        var studied: CGFloat = 0
        /// 0…1: at 1 it has had enough.
        var boredom: CGFloat = 0
        var bats = 0
        var stalls = 0
        var lastPos = V2.zero
    }
    private var toyPlay: ToyPlay?
    /// How much it feels like playing, 0…1: it builds while it has not
    /// played for a while, and is spent in playing.
    private(set) var playDrive: CGFloat = 0.5
    private var toysSeen: Set<Int> = []
    /// How used to each toy it is by now, 0 (new) … 1 (old news); it wears
    /// off over a quarter of an hour or so.
    private var toyFamiliar: [Int: CGFloat] = [:]
    /// Toys it has had enough of for now, and until when.
    private var toyRestUntil: [Int: CGFloat] = [:]
    private var toyKnocksHeard: [Int: Int] = [:]
    /// A pat under way: the front legs are up, and come down on it then.
    private var pendingBat: (id: Int, at: CGFloat, dir: V2, power: CGFloat)?
    /// The toy a leap is at, and whether it is in the air on it yet.
    private var toyPounce: Int?
    private var toyPounceFlying = false
    private var lastToyLeap: CGFloat = -9
    private var lastToyFright: CGFloat = -99
    private var toyTouchedAt: [Int: CGFloat] = [:]
    private var toyContactPos: V2?

    /// The toys here with it: on its desktop and (in a box) in the box.
    private var toysHere: [Toy] {
        guard let box = toys, box.map === map, !inHabitat else { return [] }
        return box.toys.filter { inBoxOrFree($0.pos) }
    }

    private func toy(_ id: Int) -> Toy? { toysHere.first { $0.id == id } }

    /// Free to go and play: on something, awake, and nothing more pressing.
    private var canPlayWithToys: Bool {
        mode == .attached && !config.paused && !dormant && !inCinema && laser == nil && departing == nil
            && homing == nil && build == nil && peek == nil && cursorHunt == .none && caught == nil
            && friendChase == nil && friendFlee == nil && !(confined && !inBox) && !hangOnly && t > escapeUntil
    }

    /// How fast it comes to feel like playing again.
    private var playDriveRate: CGFloat {
        let P = personality
        return lerp(0.004, 0.018, P.playfulness) * lerp(0.7, 1.3, P.energy) * lerp(1.2, 0.6, P.laziness) * lerp(1, 0.4, drowsy)
    }

    /// You put a toy out: it sees it arrive.
    func seeToy(_ toy: Toy) {
        toysSeen.insert(toy.id)
        memory?.meet(toy.kind.memoryName)
        guard !dormant, !inHabitat, !config.paused else { return }
        wake()
        // Something new: that is always worth a look.
        playDrive = max(playDrive, 0.6)
        toyFamiliar[toy.id] = 0
        setEmote(.question, 0.8)
        if mode == .attached, toyPlay == nil, [.rest, .idle, .look, .groom, .fidget].contains(activity) {
            decisionIn = min(decisionIn, 0.6)
        }
    }

    private func updateToys(dt: CGFloat) {
        let here = toysHere
        let vNow = (toyContactPos.map { dt > 0 ? (pos - $0) / dt : .zero } ?? .zero).clampedLength(1200)
        toyContactPos = pos
        playDrive = clamp(playDrive + dt * (toyPlay == nil ? playDriveRate : -0.004), 0, 1)
        for (k, v) in toyFamiliar { toyFamiliar[k] = v * exp(-dt / 900) }
        guard let box = toys, !here.isEmpty else {
            toyPlay = nil
            pendingBat = nil
            toyPounce = nil
            return
        }
        let sc = config.scale
        let P = personality

        // Whatever it runs into, lands on or is flung through gets knocked;
        // one that rolls into it sitting still comes off its legs.
        for toy in here where !toy.held || toy.dangling {
            let d = toy.pos - pos
            // (A feather is all fluff: easier to get a leg to.)
            guard d.length < toy.radius + (toy.kind.flutters ? 19 : 13) * sc else { continue }
            if toy.dangling {
                // A leg on the feather on the end of your string: as often as
                // not it gets hold of it and hauls it down with it on the
                // string; otherwise a swat that sets it swinging.
                guard t - (toyTouchedAt[toy.id] ?? -9) > 0.4 else { continue }
                toyTouchedAt[toy.id] = t
                if mode == .airborne, chance(0.45 + learned.prowess) {
                    toy.bat(vel * 0.8 + V2(0, -250), map: box.map)
                    caughtToy(toy)
                } else if mode == .airborne {
                    toy.bat(d.normalized * 160 + vNow * 0.3, map: box.map)
                    battedToy(toy)
                } else {
                    toy.bat(d.normalized * 90 + vNow * 0.3, map: box.map)
                }
                continue
            }
            if mode == .airborne, toyPounce == toy.id {
                toy.pin(for: 1.4)
                caughtToy(toy)
                continue
            }
            guard toy.pinnedFor <= 0 else { continue }
            if vNow.length > 20, d.dot(vNow) > 0 {
                if mode == .attached {
                    // Walking into it pushes it along ahead.
                    toy.shove(vNow * 1.15, map: box.map)
                } else if t - (toyTouchedAt[toy.id] ?? -9) > 0.3 {
                    toyTouchedAt[toy.id] = t
                    toy.bat(vNow * 0.55 + d.normalized * 60, map: box.map)
                }
            } else if vNow.length <= 20 {
                toy.bump(d.normalized, map: box.map)
            }
        }

        // The front legs coming down on it.
        if let b = pendingBat, t >= b.at {
            pendingBat = nil
            if let toy = toy(b.id), !toy.held || toy.dangling, toy.pos.distance(to: pos) < toy.radius + 40 * sc {
                toy.bat(b.dir * b.power, map: box.map)
                battedToy(toy)
            } else if chance(0.4) {
                setEmote(.question, 0.7)
            }
        }

        // Gathering for a leap at something in the air: the aim follows it
        // until the moment it goes.
        if let id = toyPounce, mode == .attached, activity == .crouch, pendingJump != nil, let toy = toy(id),
           toy.dangling || toy.airborne {
            let aim = toy.pos + toy.vel * 0.3
            if ballistic(from: pos, to: aim) != nil { pendingJump = aim }
        }

        // A leap at a toy, over: on it, or not.
        if toyPounce != nil {
            if mode == .airborne { toyPounceFlying = true }
            else if mode == .attached, toyPounceFlying || (pendingJump == nil && ![.crouch, .turn].contains(activity)) {
                if toyPounceFlying, let id = toyPounce, let toy = toy(id), toy.pinnedFor <= 0,
                   toy.pos.distance(to: pos) < toy.radius + 26 * sc, !toy.held {
                    toy.pin(for: 1.2)
                    caughtToy(toy)
                } else if toyPounceFlying, toyPounce.flatMap({ toy($0) })?.held != true {
                    toyPlay?.boredom += 0.04
                }
                toyPounce = nil
                toyPounceFlying = false
            } else if mode != .attached {
                toyPounce = nil
                toyPounceFlying = false
            }
        }

        // Spotting them: at once if it is moving or ringing and near.
        let asleep = activity == .sleep || dormant || inHammock
        for toy in here where !toysSeen.contains(toy.id) && toy.alpha > 0.5 {
            let sight = (asleep ? 90 : 360) * sc
            let dd = toy.pos.distance(to: pos)
            let lively = toy.speed > 15 || toy.ring > 0.1 || toy.dangling || toy.walking
            guard dd < sight, !inCinema else { continue }
            let rate = (lively ? 1.6 : 0.35) * remap(dd, 0, sight, 3, 0.4) * (asleep ? 0.3 : 1) * lerp(0.6, 1.4, P.curiosity)
            guard chance(rate * dt) else { continue }
            toysSeen.insert(toy.id)
            memory?.meet(toy.kind.memoryName)
            if mode == .attached, toyPlay == nil, !asleep {
                setEmote(lively ? .exclaim : .question, 0.9)
                decisionIn = min(decisionIn, 0.5)
            }
        }

        // A jingle: it looks round to see — right up close and loud, a
        // nervous one jumps.
        for toy in here where toy.knocks != toyKnocksHeard[toy.id] ?? 0 {
            toyKnocksHeard[toy.id] = toy.knocks
            let dd = toy.pos.distance(to: pos)
            guard dd < 700 * sc, toy.lastKnock > 0.2, !dormant else { continue }
            toysSeen.insert(toy.id)
            // Its own doing: no surprise.
            if toyPlay?.id == toy.id, toyPlay?.stage == .play { continue }
            if dd < 150 * sc, toy.lastKnock > 0.5, t - lastToyFright > 4, chance(lerp(0.7, 0.05, P.bravery)) {
                toyFright(from: toy)
            } else if toyPlay == nil {
                noticeCommotion(at: toy.pos, fright: false)
            }
        }

        // Something rolling or flying straight at it: a jump out of the way
        // for a timid one, a trap with the front legs for a bold one.
        if mode == .attached, !isHeld, ![.crouch, .turn, .shoot, .eat, .startle].contains(activity), pendingJump == nil,
           t - lastToyFright > 2.5 {
            for toy in here where !toy.held && toy.pinnedFor <= 0 && toy.id != towLine?.toy {
                let rel = pos - toy.pos
                let closing = toy.vel.dot(rel.normalized)
                guard closing > 110 * sc, rel.length < 85 * sc, rel.length > 18 * sc else { continue }
                toysSeen.insert(toy.id)
                if chance(lerp(0.85, 0.12, (P.bravery + P.playfulness) / 2)) {
                    toyFright(from: toy)
                } else {
                    lastToyFright = t
                    wake()
                    queued = nil
                    walkThen = nil
                    beginActivity(.curious, dur: randRange(0.5, 0.7))
                    if toyPlay == nil { startToyPlay(toy) }
                }
                break
            }
        }

        // You are playing with one: it goes for it, like the dot — the
        // playful straight away, the lazy when they get round to it, and
        // one that has only just had enough of it, less keenly.
        if let toy = here.first(where: { $0.inPlay }), toyPlay?.id != toy.id, canPlayWithToys,
           ![.crouch, .turn, .shoot, .eat].contains(activity) {
            toysSeen.insert(toy.id)
            let rested = t >= toyRestUntil[toy.id] ?? 0 || toy.dangling
            let eager = lerp(1, 6, P.playfulness) * lerp(1, 0.45, P.laziness) * lerp(1, 0.4, drowsy) * (rested ? 1 : 0.25)
            if chance(eager * dt) {
                // (A leap only goes from a crouch: any other left over is stale.)
                pendingJump = nil
                wake()
                startToyPlay(toy)
                if mode == .attached { decisionIn = min(decisionIn, 0.15) }
            }
        }

        // What it is playing with: still there, and how tired of it it is.
        if let play = toyPlay {
            guard let toy = toy(play.id) else {
                // Gone: a look round for it.
                endToyPlay(bored: false)
                if mode == .attached, activity == .idle || activity == .look { beginActivity(.look, dur: randRange(0.8, 1.4)) }
                return
            }
            if dormant || inCinema || departing != nil || laser != nil { endToyPlay(bored: false); return }
            let fam = toyFamiliar[toy.id] ?? 0
            let lively = toy.speed > 40 * sc || toy.dangling || toy.walking || toy.ring > 0.2
            // Never tired of it while you have hold of it, and hardly while
            // you are throwing it about.
            if play.stage != .retreat, !toy.held {
                toyPlay!.boredom += dt * lerp(0.03, 0.009, P.playfulness) * (lively ? 0.35 : 1) * lerp(0.7, 1.4, fam) * lerp(1, 1.6, drowsy)
                    * (toy.inPlay ? 0.3 : 1)
            }
            if play.stage == .investigate, mode == .attached {
                let comfort = toyComfort(fam)
                if toy.pos.distance(to: pos) < comfort + 60 * sc { toyPlay!.studied += dt }
            }
        }
    }

    /// How close it will come to something it does not know yet.
    private func toyComfort(_ fam: CGFloat) -> CGFloat {
        lerp(95, 40, personality.bravery) * lerp(1, 0.6, fam) * config.scale
    }

    /// A jump at a toy coming at it, or jingling right by it.
    private func toyFright(from toy: Toy) {
        lastToyFright = t
        guard mode == .attached, !isHeld else { return }
        wake()
        queued = nil
        walkThen = nil
        pendingBat = nil
        startled.velocity = 9 * lerp(1.3, 0.7, personality.bravery)
        setEmote(.exclaim, 0.7)
        if surfaceNormal.y > 0.85 {
            startleHop(awayFrom: toy.pos)
        } else {
            beginActivity(.startle, dur: 0.55)
        }
        // A timid one keeps its distance for a while after that.
        if personality.bravery < 0.5 {
            if toyPlay == nil || toyPlay?.id == toy.id {
                toyPlay = ToyPlay(id: toy.id, stage: .retreat, since: toyPlay?.since ?? t, stageSince: t)
            }
        }
    }

    private func startToyPlay(_ toy: Toy) {
        let fam = max(toyFamiliar[toy.id] ?? 0, min((memory?.familiarity(with: toy.kind.memoryName).times ?? 0) / 8, 1))
        // Straight in — unless it is a timid one, and this is new to it: then
        // it looks it over first.
        let straightIn = personality.bravery >= 0.4 || fam > 0.3 || toy.dangling
        toyPlay = ToyPlay(id: toy.id, stage: straightIn ? .play : .investigate, since: t, stageSince: t, lastPos: pos)
        toysSeen.insert(toy.id)
        queued = nil
        walkThen = nil
    }

    /// Picks a toy to go and play with, if it feels like it: the likelier
    /// the more it wants to play, the more the toy draws it — new, on the
    /// move, jingling, dangled for it, a favourite — and the nearer it is.
    private func pickToy() -> Bool {
        guard canPlayWithToys else { return false }
        let sc = config.scale
        var best: (score: CGFloat, toy: Toy)?
        for toy in toysHere where toysSeen.contains(toy.id) && (!toy.held || toy.dangling) && t >= toyRestUntil[toy.id] ?? 0 {
            let d = toy.pos.distance(to: pos)
            guard d < 900 * sc else { continue }
            let fam = toyFamiliar[toy.id] ?? 0
            let fond = memory?.fondness(of: toy.kind.memoryName) ?? 0
            let astir = toy.dangling ? 2.5 : min(toy.speed / (120 * sc), 1.5) + toy.ring + (toy.walking ? 1 : 0)
            let score = toy.kind.lure * (1 + astir) * lerp(1.4, 0.55, fam) * (1 + fond * 0.6) / (1 + d / (350 * sc))
            if best == nil || score > best!.score { best = (score, toy) }
        }
        guard let b = best else { return false }
        let P = personality
        let want = playDrive * lerp(0.3, 1.2, P.playfulness) * lerp(0.7, 1.2, P.curiosity) * b.score * lerp(1, 0.35, drowsy) * 0.7
            + (b.toy.dangling ? 0.35 : 0)
        guard chance(min(0.85, want)) else { return false }
        startToyPlay(b.toy)
        return true
    }

    /// Had enough (or had it taken away).
    private func endToyPlay(bored: Bool) {
        guard let play = toyPlay else { return }
        toyPlay = nil
        pendingBat = nil
        guard bored else { return }
        let P = personality
        let fam = min(1, (toyFamiliar[play.id] ?? 0) + 0.3)
        toyFamiliar[play.id] = fam
        toyRestUntil[play.id] = t + lerp(40, 15, P.playfulness) * (1 + fam)
        playDrive *= lerp(0.2, 0.5, P.playfulness)
        guard mode == .attached else { return }
        queued = nil
        walkThen = nil
        // A good game leaves it pleased with itself; a dull one, it just
        // wanders off.
        if play.bats >= 3, chance(0.5) {
            beginActivity(.wiggle, dur: 0.8)
            setEmote(chance(0.5) ? .note : .hearts, 1.1)
        } else if chance(lerp(0.2, 0.6, P.laziness)) {
            beginActivity(.rest, dur: randRange(3, 7))
        } else if chance(0.5) {
            beginActivity(.groom, dur: randRange(1.4, 2.4))
        } else {
            turnTo(-walkDir, then: .walk, for: randRange(1.2, 2.6))
        }
        decisionIn = max(decisionIn, 2)
    }

    /// A pat that landed.
    private func battedToy(_ toy: Toy) {
        remember(.played, 0.1)
        memory?.warm(to: toy.kind.memoryName, by: 0.02)
        happy.velocity = max(happy.velocity, 3)
        if chance(0.2) { setEmote(chance(0.5) ? .sparkle : .note, 0.7) }
        guard toyPlay?.id == toy.id else { return }
        toyPlay!.bats += 1
        toyPlay!.boredom += 0.06 * (0.6 + (toyFamiliar[toy.id] ?? 0))
    }

    /// Got it: pinned under it, or the feather on your string.
    private func caughtToy(_ toy: Toy) {
        let fromYou = toy.dangling
        remember(.played, fromYou ? 0.5 : 0.25)
        memory?.warm(to: toy.kind.memoryName, by: 0.04)
        happy.velocity = 6
        setEmote(.sparkle, 0.8)
        toyPounce = nil
        toyPounceFlying = false
        if toy.kind.windsUp, (memory?.familiarity(with: toy.kind.memoryName).times ?? 0) < 4 || chance(0.15) {
            // It looked like a bug.
            think(.text(chance(0.5) ? "crunchy…?" : "tin?"), for: 2)
        }
        if toyPlay?.id == toy.id {
            toyPlay!.bats += 1
            toyPlay!.boredom += 0.08
        } else if toyPlay == nil, canPlayWithToys || mode == .airborne {
            startToyPlay(toy)
        }
        queue(chance(0.5) ? .peer : .wiggle, randRange(0.7, 1.1))
    }

    /// One decision's worth of playing.
    private func playWithToy() {
        guard let play = toyPlay, let toy = toy(play.id) else {
            endToyPlay(bored: false)
            return
        }
        // Held up a moment (getting out from under a window, say): the game
        // is still on once that is done.
        guard canPlayWithToys else { return }
        // Hauling it off on a line: that walk plays out first.
        if towLine != nil {
            decisionIn = 0.3
            return
        }
        let P = personality
        let sc = config.scale
        decisionIn = toy.inPlay ? randRange(0.15, 0.35) : randRange(0.25, 0.6)
        if play.boredom >= 1 || (!toy.inPlay && t - play.since > lerp(45, 120, P.playfulness)) {
            endToyPlay(bored: true)
            return
        }
        // Getting nowhere (a covered stretch in the way, say): it tires of
        // it all the quicker.
        if pos.distance(to: play.lastPos) < 6 * sc, [.walk, .sneak, .scurry].contains(activity) || activity == .idle {
            toyPlay!.stalls += 1
            if toyPlay!.stalls > 5, !toy.held { toyPlay!.boredom += 0.1 }
        } else {
            toyPlay!.stalls = 0
        }
        toyPlay!.lastPos = pos
        let d = toy.pos - pos
        let dist = d.length
        let fam = toyFamiliar[toy.id] ?? 0
        switch play.stage {
        case .retreat:
            // Keeping its distance, watching; then back for another look,
            // or it leaves the thing be.
            if t - play.stageSince > lerp(7, 2.5, P.bravery) {
                if chance(lerp(0.3, 0.9, P.curiosity)) {
                    toyPlay!.stage = .investigate
                    toyPlay!.stageSince = t
                    beginActivity(.look, dur: randRange(0.6, 1.2))
                } else {
                    endToyPlay(bored: true)
                }
            } else if dist < lerp(160, 80, P.bravery) * sc, let dir = alongEdge(to: toy.pos) {
                turnTo(-dir, then: .scurry, for: randRange(0.4, 0.8))
            } else {
                beginActivity(.look, dur: randRange(0.6, 1.2))
            }
        case .investigate:
            let comfort = toyComfort(fam)
            if dist > comfort + 40 * sc {
                if !approachToy(toy.pos, style: P.bravery < 0.4 ? .sneak : .walk, stop: comfort) {
                    beginActivity(.look, dur: randRange(0.6, 1.0))
                }
                return
            }
            let need = lerp(2.5, 0.8, P.curiosity) * lerp(1, 0.4, fam)
            if play.studied > need {
                // It has the measure of it now.
                toyPlay!.stage = .play
                toyPlay!.stageSince = t
                toyFamiliar[toy.id] = max(fam, 0.2)
                setEmote(chance(0.5) ? .sparkle : .note, 0.8)
                beginActivity(chance(0.5) ? .wiggle : .bounce, dur: randRange(0.6, 0.9))
                return
            }
            // Sizing it up: face it, and a good look — nose down to it, or
            // a front leg out to feel.
            if let dir = alongEdge(to: toy.pos), dir != walkDir {
                turnTo(dir, then: .look, for: randRange(0.5, 0.9))
                return
            }
            let r = CGFloat.random(in: 0...1)
            if r < 0.35 {
                beginActivity(.peer, dur: randRange(1.0, 1.6))
            } else if r < 0.65 {
                beginActivity(.curious, dur: randRange(0.9, 1.5))
                if chance(0.4) { setEmote(.question, 1.0) }
            } else if dist > toy.radius + 30 * sc, chance(lerp(0.2, 0.7, P.bravery)) {
                // A step closer.
                approachToy(toy.pos, style: .sneak, stop: toy.radius + 24 * sc)
            } else {
                beginActivity(.look, dur: randRange(0.7, 1.3))
            }
        case .play:
            playMove(toy, dist: dist)
        }
    }

    /// Playing proper: after it, at it, and batting it about.
    private func playMove(_ toy: Toy, dist: CGFloat) {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        let P = personality
        let sc = config.scale
        let seg = loop.segs[anchor.segIdx]
        let d = toy.pos - pos
        let along = d.dot(seg.dir)
        let off = abs(d.dot(seg.normal))
        let pounceKeen = lerp(0.2, 0.75, (P.playfulness + P.bravery + P.energy) / 3)

        // In your hand: waiting for the throw — under it if it is near,
        // eyes on it, up on its toes and wiggling.
        if toy.held, !toy.dangling {
            if abs(along) > 60 * sc, dist < 500 * sc {
                approachToy(pos + seg.dir * along, style: .scurry, stop: 30 * sc, leap: false)
            } else {
                let r = CGFloat.random(in: 0...1)
                let a: Activity = r < 0.45 ? .curious : r < 0.7 ? .look : r < 0.85 ? .hop : .wiggle
                beginActivity(a, dur: a == .hop ? Spider.hopDur : randRange(0.4, 0.8))
            }
            return
        }

        // Up in the air — on your string, drifting down, bouncing: under
        // it, and a leap at it when it is low enough to reach.
        if toy.dangling || (toy.airborne && toy.speed > 10) {
            let aim = toy.pos + toy.vel * 0.25
            if dist < 230 * sc, dist > 40 * sc, t - lastToyLeap > 1.3, chance(pounceKeen + (toy.dangling ? 0.2 : 0)),
               ballistic(from: pos, to: aim) != nil, (aim - pos).normalized.dot(surfaceNormal) > 0.1 {
                pounceToy(toy, at: aim)
            } else if abs(along) > 45 * sc {
                approachToy(pos + seg.dir * along, style: .scurry, stop: 20 * sc, leap: false)
            } else if chance(0.5) {
                beginActivity(.hop, dur: Spider.hopDur)
            } else {
                beginActivity(.curious, dur: randRange(0.5, 0.9))
            }
            return
        }

        let reach = toy.radius + 30 * sc
        let lively = toy.speed > 45 * sc || toy.walking
        // Held down under it just now: a closer look before the next go.
        if toy.pinnedFor > 0, dist < reach {
            beginActivity(chance(0.6) ? .peer : .curious, dur: randRange(0.6, 1.0))
            return
        }
        // Right by it: a pat to send it off — or, if it is scuttling
        // about, a pounce to stop it.
        if abs(along) < reach, off < 32 * sc {
            let dir: CGFloat = along >= 0 ? 1 : -1
            if dir != walkDir {
                turnTo(dir, then: .look, for: 0.2)
                return
            }
            // Or, now and then, a line hitched to it, to haul it off.
            if startTow(toy, toward: dir) { return }
            let loft = CGFloat.random(in: toy.kind.batLoft)
            let push = (seg.dir * dir * cos(loft) + seg.normal * sin(loft)).normalized
            let power = lerp(150, 330, (P.energy + P.playfulness) / 2) * randRange(0.8, 1.2) * sc.squareRoot()
            beginActivity(.curious, dur: randRange(0.5, 0.65))
            pendingBat = (toy.id, t + 0.28, push, power)
            return
        }
        // Off it goes: after it, and a pounce when it is in range.
        if lively {
            let aim = toy.pos + toy.vel * 0.35
            if dist < 150 * sc, dist > 45 * sc, t - lastToyLeap > 1.2, toy.onSurface, chance(pounceKeen),
               let spot = map.nearestSpot(to: aim, within: 40 * sc), ballistic(from: pos, to: spot.point) != nil {
                pounceToy(toy, at: spot.point)
            } else {
                approachToy(aim, style: .scurry, stop: 10 * sc)
            }
            return
        }
        // Sitting still some way off: over to it — now and then with a
        // pounce from a little way off, just for the fun of it.
        if dist < 130 * sc, dist > 50 * sc, t - lastToyLeap > 2, chance(pounceKeen * 0.4), toy.onSurface,
           let spot = map.nearestSpot(to: toy.pos, within: 40 * sc), ballistic(from: pos, to: spot.point) != nil {
            pounceToy(toy, at: spot.point)
            return
        }
        let hurry = toy.inPlay || chance(lerp(0.2, 0.7, P.energy))
        if !approachToy(toy.pos, style: hurry ? .scurry : .walk, stop: toy.radius + 16 * sc) {
            beginActivity(.look, dur: randRange(0.4, 0.8))
        }
    }

    private func pounceToy(_ toy: Toy, at point: V2) {
        toyPounce = toy.id
        toyPounceFlying = false
        lastToyLeap = t
        queued = nil
        walkThen = nil
        if let dir = alongEdge(to: point), dir != walkDir {
            startJump(to: point)
        } else {
            pendingJump = point
            beginActivity(.crouch, dur: randRange(0.28, 0.42))
        }
    }

    /// Which way along its edge `p` is, if it is standing on one.
    private func alongEdge(to p: V2) -> CGFloat? {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return nil }
        return (p - pos).dot(loop.segs[anchor.segIdx].dir) >= 0 ? 1 : -1
    }

    /// Toward `p` at `style`, stopping `stop` short: along its edge if that
    /// is the way, round its window if it is on the same one, and otherwise
    /// a leap to wherever gets it nearest. False if it is there already.
    @discardableResult
    private func approachToy(_ p: V2, style: Activity, stop: CGFloat, leap: Bool = true) -> Bool {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return false }
        let sc = config.scale
        let seg = loop.segs[anchor.segIdx]
        let d = p - pos
        let along = d.dot(seg.dir)
        let off = abs(d.dot(seg.normal))
        let pace = config.walkSpeed * (style == .scurry ? 2.6 : style == .sneak ? 0.42 : 1)
        if off < 45 * sc || (abs(along) > off * 2 && abs(along) < 260 * sc) || !leap {
            guard abs(along) > stop else { return false }
            let dir: CGFloat = along >= 0 ? 1 : -1
            turnTo(dir, then: style, for: clamp((abs(along) - stop) / max(pace, 1), 0.3, 2.2))
            return true
        }
        // Round its own window to it, when it is on the same one.
        if let spot = map.nearestSpot(to: p, within: 50 * sc), spot.loop.id == anchor.loopID, spot.anchor.segIdx != anchor.segIdx {
            var way: (d: CGFloat, dir: CGFloat)?
            for dir in [CGFloat(1), -1] {
                if let dd = loopDistance(loop, to: spot.anchor, dir: dir), way == nil || dd < way!.d { way = (dd, dir) }
            }
            if let w = way, w.d < 900 * sc {
                turnTo(w.dir, then: style == .sneak ? .walk : style, for: clamp(w.d / max(pace, 1), 0.6, 3.0))
                return true
            }
        }
        var best: (d: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) where inBoxOrFree(spot.point) {
            let dd = spot.point.distance(to: p)
            guard dd < d.length - 20, spot.point.distance(to: pos) > 40 * sc else { continue }
            guard let launch = ballistic(from: pos, to: spot.point), launch.normalized.dot(surfaceNormal) > -0.15 else { continue }
            if best == nil || dd < best!.d { best = (dd, spot.point) }
        }
        if let b = best {
            startJump(to: b.point)
        } else {
            walkToward(p)
        }
        return true
    }

    /// Tools only: what it is up to with the toys.
    var debugToy: String {
        guard let p = toyPlay else { return String(format: "- drive %.2f", Double(playDrive)) }
        return String(format: "%@ #%d bats %d bored %.2f drive %.2f", "\(p.stage)", p.id, p.bats, Double(p.boredom), Double(playDrive))
    }
    var debugToysSeen: Int { toysSeen.count }
    /// Tools only: whatever is keeping it from playing right now.
    var debugToyBlock: String {
        let checks: [(Bool, String)] = [
            (mode != .attached, "mode"), (dormant, "dormant"), (inCinema, "cinema"), (laser != nil, "laser"),
            (departing != nil, "departing"), (homing != nil, "homing"), (build != nil, "build"), (peek != nil, "peek"),
            (cursorHunt != .none, "cursorHunt"), (caught != nil, "caught"), (friendChase != nil || friendFlee != nil, "friend"),
            (confined && !inBox, "outOfBox"), (hangOnly, "hangOnly"), (t <= escapeUntil, "escaping"),
        ]
        return checks.filter(\.0).map(\.1).joined(separator: ",")
    }

    // MARK: Traces
    //
    // What it leaves about the desktop as it goes (see Traces.swift): now
    // and then a line paid out behind a leap and fastened where it lands;
    // the line it came down on, left where it stepped off; a little web in
    // a corner or under a ledge; its catch carried off somewhere quieter to
    // be eaten, and what is left of it; a toy hauled off on a line.

    /// Where it leaves them. Nil — a visitor, the Studio, the tools — and
    /// it leaves nothing.
    var traces: TraceKeeper?
    /// Tools only: odds for every leave-a-trace draw, in place of their own.
    static var debugTraceOdds: CGFloat?
    /// The line paying out behind a leap.
    private var leapLine: Int?
    /// A toy it is hauling off on a line: round with its back to it, a dab
    /// of silk on it, and off it walks with it in tow.
    private struct Tow {
        var toy: Int
        var strand: Int?
        var since: CGFloat
        var walkFor: CGFloat
        var walkingSince: CGFloat?
    }
    private var towLine: Tow?
    /// Taking its catch somewhere quieter to eat it.
    private var mealCarry: (to: V2, since: CGFloat)?
    /// A web it means to spin, or is spinning.
    private struct WebJob {
        var loopID: String
        /// Where it stands to spin it.
        var stand: V2
        /// A corner — the point, and a spot a little way along each side
        /// of it — or a spot under a ledge.
        var corner: (o: V2, a: V2, b: V2)?
        var under: V2?
        var size: CGFloat
        var web: Int?
        var since: CGFloat
    }
    private var webJob: WebJob?
    private var lastTremble: CGFloat = -9

    /// It may leave traces here: it has somewhere to leave them, and is out
    /// on the desktop they are for.
    private var leavesTraces: Bool {
        guard let k = traces, k.enabled, k.map === map else { return false }
        return !inHabitat && !inCinema
    }

    private func traceOdds(_ p: CGFloat) -> Bool { chance(Spider.debugTraceOdds ?? p) }

    /// The tip of the abdomen, where the silk comes from, in the world.
    private func spinneretsWorld() -> V2 {
        let ab = SpiderRenderer.abdomen(for: look)
        return toWorld(V2(ab.c.x - ab.rx + 3, ab.c.y))
    }

    /// The ledge under it as a spot the silk can be stuck to.
    private func ledgePin() -> SilkPin? {
        guard let lp = ledgePoint() else { return nil }
        return SilkPin.at(lp.point, map: map, prefer: anchor.loopID, within: map.standoff * 1.6 + 4)
    }

    /// Now and then a leap trails a line from where it went from, to be
    /// fastened where it comes down.
    private func maybeTrailLine(from pin: SilkPin?, to point: V2) {
        leapLine = nil
        guard leavesTraces, config.webs, !flyingHome, !confined, let pin, let keeper = traces else { return }
        let d = pin.last.distance(to: point)
        guard d > 90 * config.scale, d < 560 * config.scale, traceOdds(0.3) else { return }
        leapLine = keeper.beginLine(from: pin, tail: spinneretsWorld())
    }

    /// The line it was on, left behind: from where it was fastened up above
    /// to where it has stepped off onto something (`fastened`), or hanging
    /// loose from up there. False if it is not left — nothing up there to
    /// have stuck it to, or not this time — and the line goes as it always
    /// did.
    private func leaveLineBehind(fastened: Bool) -> Bool {
        guard webActive, leavesTraces, config.webs, !confined, let keeper = traces, rope.live, rope.points.count >= 2,
              traceOdds(fastened ? 0.7 : 0.5),
              let top = SilkPin.at(webAnchor, map: map, within: 8) else { return false }
        var end: SilkPin?
        if fastened {
            guard let pin = ledgePin(), pin.last.distance(to: top.last) > 50 * config.scale else { return false }
            end = pin
        }
        guard keeper.leaveLine(rope.points, from: top, to: end) != nil else { return false }
        detachWeb(fade: false)
        rope.clear()
        webAlpha.reset(0)
        return true
    }

    /// Keeps the lines it has out in step with it, once a frame.
    private func syncTraces(dt: CGFloat) {
        guard let keeper = traces else { return }
        if let id = leapLine {
            if !keeper.has(id) {
                leapLine = nil
            } else if !leavesTraces {
                keeper.letGo(id)
                leapLine = nil
            } else if mode == .airborne {
                keeper.payOut(id, tail: spinneretsWorld())
            } else {
                // Down: stuck where it landed — unless that is hardly any
                // way from where it went from, or it has come to be held
                // or hanging some other way.
                if mode == .attached, let pin = ledgePin(), let from = keeper.strand(id)?.head?.last,
                   from.distance(to: pin.last) > 60 * config.scale {
                    keeper.fasten(id, to: pin)
                } else {
                    keeper.letGo(id)
                }
                leapLine = nil
            }
        }
        if var tow = towLine {
            let stillOn = tow.strand.map { keeper.towing($0) } ?? true
            if !stillOn || mode != .attached || !leavesTraces || toy(tow.toy)?.held != false || t - tow.since > 12 {
                if let id = tow.strand, keeper.has(id) { keeper.letGo(id) }
                towLine = nil
            } else if tow.strand == nil {
                // Backed up to it, the silk goes on as the abdomen dabs it.
                if activity == .fasten, activityTime > 0.25, let toy = toy(tow.toy) {
                    tow.strand = keeper.beginTow(toy: toy, tail: spinneretsWorld())
                    towLine = tow.strand == nil ? nil : tow
                } else if t - tow.since > 3, activity != .turn, activity != .fasten {
                    towLine = nil
                }
            } else if let id = tow.strand {
                keeper.payOut(id, tail: spinneretsWorld())
                if tow.walkingSince == nil {
                    if activity != .fasten, activity != .turn {
                        tow.walkingSince = t
                        beginActivity(.walk, dur: tow.walkFor)
                    }
                    towLine = tow
                } else if let since = tow.walkingSince, activity != .walk || t - since > 7 {
                    // Far enough: it lets go of the line and turns to see
                    // what it has got.
                    keeper.letGo(id)
                    towLine = nil
                    finishTow(tow.toy)
                }
            }
        }
        if let id = webJob?.web, activity == .fasten, mode == .attached {
            keeper.spin(id, by: dt / max(activityDur * 3, 1))
        }
    }

    /// Silk somewhere shook — plucked, torn, a fly blundering into it. Near
    /// enough to feel it, it turns to look (a fly caught wakes it), and
    /// whatever is caught there is spotted.
    func feelTremble(at p: V2, strength: CGFloat) {
        guard leavesTraces, !dormant, !config.paused, mode == .attached || mode == .dangling else { return }
        guard p.distance(to: pos) < 650 * config.scale * (0.5 + strength) else { return }
        for q in prey where q.state == .loose && !q.noticed && q.pos.distance(to: p) < 30 {
            q.noticed = true
            memory?.meet(q.kind.memoryName)
        }
        guard t - lastTremble > 3, activity != .sleep || strength > 0.7 else { return }
        lastTremble = t
        guard mode == .attached, caught == nil, towLine == nil,
              [.idle, .look, .rest, .groom, .fidget, .stare, .glance, .sleep, .peer].contains(activity) else { return }
        wake()
        setEmote(strength > 0.6 ? .exclaim : .question, 0.8)
        queued = nil
        walkThen = nil
        if let dir = alongEdge(to: p), dir != walkDir, abs((p - pos).dot(surfaceNormal.perp)) > 40 * config.scale {
            turnTo(dir, then: .look, for: randRange(0.8, 1.3))
        } else {
            beginActivity(.look, dur: randRange(0.8, 1.3))
        }
        decisionIn = min(decisionIn, 0.6)
    }

    // Its catch, taken somewhere quieter.

    /// Its catch in its jaws: it settles down to eat it here — or, now and
    /// then, carries it off to the end of its ledge first, tucked into the
    /// corner there.
    private func settleToMeal(_ c: Prey) {
        queued = nil
        walkThen = nil
        let dur = c.kind.mealTime * randRange(0.9, 1.15)
        if mealCarry == nil, leavesTraces, !c.kind.bitter, c.kind != .ant, c.kind != .mosquito, traceOdds(0.55),
           let spot = quietSpot() {
            mealCarry = (spot, t)
            walkToward(spot)
            walkThen = (.eat, dur)
            return
        }
        mealCarry = nil
        beginActivity(.eat, dur: dur)
    }

    /// The nearer end of its ledge, if that is a short walk off with
    /// nothing in the way.
    private func quietSpot() -> V2? {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return nil }
        let seg = loop.segs[anchor.segIdx]
        let sc = config.scale
        var best: (d: CGFloat, p: V2)?
        for dir in [CGFloat(1), -1] {
            let end = dir > 0 ? seg.len - 22 * sc : 22 * sc
            let d = (end - anchor.t) * dir
            guard d > 50 * sc, d < 280 * sc else { continue }
            let reach = seg.limit(from: anchor.t, dir: dir)
            guard dir > 0 ? reach >= end : reach <= end else { continue }
            if best == nil || d < best!.d { best = (d, seg.point(at: end)) }
        }
        return best?.p
    }

    // A toy, hauled off.

    /// Rather than a pat, now and then it hitches a line to a toy lying
    /// still beside it, turns its back on it and hauls it off behind it
    /// along the ledge. `dir` is the way to the toy.
    private func startTow(_ toy: Toy, toward dir: CGFloat) -> Bool {
        guard towLine == nil, leavesTraces, config.webs, traces != nil, toy.onSurface, !toy.inPlay, !toy.held,
              toy.kind != .feather, toy.speed < 8, traceOdds(0.22),
              let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return false }
        // Room to walk off with it.
        let seg = loop.segs[anchor.segIdx]
        guard loop.closed || abs(seg.limit(from: anchor.t, dir: -dir) - anchor.t) > 70 * config.scale else { return false }
        towLine = Tow(toy: toy.id, strand: nil, since: t, walkFor: randRange(2.8, 4.0), walkingSince: nil)
        pendingBat = nil
        queued = nil
        walkThen = nil
        turnTo(-dir, then: .fasten, for: randRange(0.55, 0.75))
        if chance(0.3) { setEmote(.sparkle, 0.8) }
        return true
    }

    /// Hauled it far enough: round to have a look at it.
    private func finishTow(_ id: Int) {
        guard mode == .attached else { return }
        if toyPlay?.id == id {
            toyPlay!.bats += 1
            toyPlay!.boredom += 0.12
        }
        remember(.played, 0.15)
        queued = nil
        walkThen = nil
        if let toy = toy(id), let dir = alongEdge(to: toy.pos), dir != walkDir {
            turnTo(dir, then: .peer, for: randRange(0.9, 1.4))
        } else {
            beginActivity(.peer, dur: randRange(0.9, 1.4))
        }
        happy.velocity = 4
        if chance(0.4) { setEmote(chance(0.5) ? .sparkle : .note, 0.9) }
    }

    // A little web.

    /// Somewhere near to spin a little web: a corner at the end of its own
    /// ledge — the floor meeting a wall, the side of the Dock — or right
    /// here under the ledge it is hanging from. Nil if there is nowhere, or
    /// a web is there already.
    private func webSite() -> WebJob? {
        guard mode == .attached, let keeper = traces, let loop = map.loop(anchor.loopID),
              anchor.segIdx < loop.segs.count, !loop.edge.isEmpty else { return nil }
        let sc = config.scale
        let size = randRange(44, 62) * max(sc, 0.7)
        let seg = loop.segs[anchor.segIdx]
        var best: (d: CGFloat, job: WebJob)?
        let n = loop.edge.count
        for i in 0..<n where loop.closed || i + 1 < n {
            let e1 = loop.edge[i], e2 = loop.edge[(i + 1) % n]
            // Two edges meeting with the open space between them — the
            // second turning up from the first, into a corner.
            guard e1.b.distance(to: e2.a) < 1, e2.dir.dot(e1.normal) > 0.5,
                  e1.len > size * 1.4, e2.len > size * 1.4 else { continue }
            let o = e1.b
            // At an end of the stretch it is on, a short walk off.
            let (tt, off) = projectOnSegment(o, seg.a, seg.b)
            guard off < map.standoff * 1.7, tt < 1 || tt > seg.len - 1 else { continue }
            let standT = tt < 1 ? 26 * sc : seg.len - 26 * sc
            let stand = seg.point(at: standT)
            let d = stand.distance(to: pos)
            let dir: CGFloat = standT >= anchor.t ? 1 : -1
            let reach = seg.limit(from: anchor.t, dir: dir)
            guard d < 480 * sc, dir > 0 ? reach >= standT : reach <= standT,
                  !keeper.webNear(o, within: 110 * sc) else { continue }
            let job = WebJob(loopID: loop.id, stand: stand, corner: (o, o - e1.dir * size, o + e2.dir * size),
                             under: nil, size: size, web: nil, since: t)
            if best == nil || d < best!.d { best = (d, job) }
        }
        if let b = best { return b.job }
        // Under a ledge: a tangle hung from right where it is.
        if seg.facing == .down, let lp = ledgePoint(), !keeper.webNear(lp.point, within: 110 * sc),
           let e = loop.edge.first(where: { $0.facing == .down && projectOnSegment(lp.point, $0.a, $0.b).dist < 3 }) {
            let t0 = projectOnSegment(lp.point, e.a, e.b).t
            guard t0 > size, t0 < e.len - size else { return nil }
            return WebJob(loopID: loop.id, stand: pos, corner: nil, under: lp.point, size: size * 0.8, web: nil, since: t)
        }
        return nil
    }

    /// One step of spinning a web: over to the spot, round with its tail to
    /// where the web goes, and a few dabs to stick the threads down, the
    /// web growing with each; then a look at its work.
    private func pursueWeb() {
        guard var job = webJob, let keeper = traces else { return }
        decisionIn = 0.2
        guard leavesTraces, t - job.since < 40, mode == .attached, anchor.loopID == job.loopID else {
            webJob = nil
            return
        }
        if let id = job.web {
            if (keeper.web(id)?.progress ?? 1) >= 1 {
                webJob = nil
                beginActivity(.peer, dur: randRange(1.0, 1.6))
                if chance(0.5) { setEmote(.sparkle, 0.9) }
                remember(.played, 0.05)
                return
            }
            beginActivity(.fasten, dur: randRange(1.2, 1.6))
            return
        }
        if pos.distance(to: job.stand) > 20 * config.scale {
            walkToward(job.stand)
            activityDur = min(activityDur, max(pos.distance(to: job.stand) / max(config.walkSpeed * 0.9, 1), 0.4))
            return
        }
        // Tail to the corner.
        if let c = job.corner, let dir = alongEdge(to: c.o), dir == walkDir {
            turnTo(-dir, then: .idle, for: 0.1)
            return
        }
        if let c = job.corner {
            job.web = keeper.startWeb(corner: c.o, a: c.a, b: c.b)
        } else if let u = job.under {
            job.web = keeper.startWeb(under: u, size: job.size)
        }
        guard job.web != nil else { webJob = nil; return }
        webJob = job
        beginActivity(.fasten, dur: randRange(1.2, 1.6))
    }

    /// Tools only: what it has left about.
    var debugTraces: String {
        var s = traces?.debugSummary ?? "none"
        if leapLine != nil { s += " | leap line out" }
        if towLine != nil { s += " | towing" }
        if mealCarry != nil { s += " | carrying" }
        if let j = webJob { s += " | web job \(j.web.map { "#\($0)" } ?? "planned")" }
        return s
    }
    var debugCarrying: Bool { mealCarry != nil && caught != nil }
    var debugTowing: Bool { towLine != nil }

    /// Tools only: has it in its jaws, as if it had just caught it.
    func debugCatch(_ p: Prey) { catchPrey(p) }

    /// Tools only: pays out a line from where it is and goes down it.
    func debugRappel() {
        guard mode == .attached else { return }
        dropOnWeb()
    }

    /// Tools only: hitches a line to the nearest toy, the one it is facing,
    /// and hauls it off.
    func debugTow() -> Bool {
        guard let toy = toysHere.min(by: { $0.pos.distance(to: pos) < $1.pos.distance(to: pos) }),
              let dir = alongEdge(to: toy.pos), dir == walkDir else { return false }
        if toyPlay == nil { startToyPlay(toy) }
        return startTow(toy, toward: dir)
    }

    /// Tools only: sets about spinning a web, if there is somewhere near.
    func debugSpinWeb() -> Bool {
        guard let site = webSite() else { return false }
        webJob = site
        queued = nil
        walkThen = nil
        beginActivity(.idle, dur: 0.1)
        decisionIn = 0
        return true
    }

    // MARK: Silk line

    /// Where the silk leaves the body, in sprite units: the spinnerets when
    /// it hangs in line with the thread, the top of the abdomen when it is
    /// slung under a swing.
    private func silkAttachLocal() -> V2 {
        // On a line: hanging, from the spinnerets; climbing, it hugs the
        // line, the silk along its belly with its feet holding it, and holds
        // it there (see `climbHold`); turning end for end between the two,
        // drawn in to its middle (see `turnPivot`). Shooting a line in
        // mid-air, with its rear brought round to the mark: the spinnerets.
        if mode == .dangling {
            let g = smoothstep(lineGrip)
            return g > 0 ? V2.lerp(lineStance, turnPivot, g) : lineStance
        }
        if mode == .airborne && (airShot != nil || draglineCatchY != nil) { return spinnerets }
        let ab = SpiderRenderer.abdomen(for: look)
        return V2(ab.c.x, ab.c.y + ab.ry - 2)
    }

    /// The spinnerets, in sprite units: the tip of the abdomen.
    private var spinnerets: V2 {
        let ab = SpiderRenderer.abdomen(for: look)
        return V2(ab.c.x - ab.rx + 3, ab.c.y)
    }

    /// Climbing, it hugs the line: the silk runs along its belly, tucked in
    /// against the underside of its abdomen — as near its middle as a line
    /// along the outside of it can be — with its legs reaching up and down
    /// it. This is where the line comes up past the lowest of its feet, and
    /// where it meets the silk it has hauled in, looping back from its
    /// spinnerets.
    private var climbHold: V2 { bellyLine(spinnerets.x - 25) }

    /// The line the silk runs along climbing, at `x` along the body: just
    /// inside the belly's outline under the middle of the abdomen, and from
    /// there on, leaning back with the body (`lineTilt`).
    private func bellyLine(_ x: CGFloat) -> V2 {
        let ab = SpiderRenderer.abdomen(for: look)
        return V2(x, ab.c.y - ab.ry + 2 + (ab.c.x - x) * tan(Spider.climbLean))
    }

    /// Turning end for end on a line, what it turns about: its middle, at
    /// the waist, where its legs gather the line in against its belly —
    /// its weight all but under its own grip, so it rolls over in its
    /// place rather than swinging round on the end of its abdomen.
    private var turnPivot: V2 {
        let ab = SpiderRenderer.abdomen(for: look)
        return bellyLine(ab.c.x + ab.rx * 0.75)
    }

    /// Where the line leaves the body on it, but for drawing it in to turn:
    /// hanging, the spinnerets; climbing, its hold along the belly.
    private var lineStance: V2 {
        climbLayout > 0 ? V2.lerp(spinnerets, climbHold, climbLayout) : spinnerets
    }

    /// Hanging on a line, or dropping on its dragline: its legs have the
    /// line either way.
    private var onLine: Bool { mode == .dangling || (mode == .airborne && draglineCatchY != nil && webActive) }

    /// How far into its climbing stance it is on a line, 0…1. It turns into
    /// it as it comes round head up to climb, and out of it as it goes back
    /// round to hang — never merely because it happens to be lying across
    /// the line (taken to it sideways, or swinging hard).
    private var climbLayout: CGFloat = 0

    /// How long the line is with it at the top: climbing head up, its head
    /// is just under whatever the line hangs from; hanging head down, its
    /// spinnerets are. (By how far round it really is, so a climb decided
    /// on close under the top does not count it there before it has turned.)
    private var lineTop: CGFloat {
        let h = SpiderRenderer.head(for: look)
        return lerp(26, h.c.x + h.r - climbHold.x + 5, climbLayout) * config.scale
    }

    private func silkAttachWorld() -> V2 {
        toWorld(silkAttachLocal())
    }

    /// On a line, where it is fastened to the body has moved since last
    /// frame — drawn in to its middle to turn, or let back out after: the
    /// line is measured again to there, as the body is now, so the body
    /// stays where it is and only the line's end moves — taken in or let
    /// out a little, and swinging gently to hang under it. Whatever length
    /// it was making for, it still makes for, in the same terms — and one
    /// that would take it to the top still takes it all the way up.
    private func reattach() {
        let a = silkAttachLocal()
        defer { attachWas = a }
        guard let was = attachWas, a.distance(to: was) > 0.0001 else { return }
        var d = a - was
        d.x *= mirrorSign
        let len = max(webLen + bungee.value, 20)
        let end = webAnchor + V2(sin(webAngle), -cos(webAngle)) * len + d.rotated(by: heading) * config.scale
        let r = end - webAnchor
        guard r.length > 20 else { return }
        let change = r.length - len
        webLen += change
        webAngle = atan2(r.x, -r.y)
        if webLenTarget >= lineTop + 8 * config.scale { webLenTarget += change }
        prevHangLen += change
        lineRef += change
        // (Back where it hangs from, the terms are that again.)
        if lineGrip <= 0, climbLayout <= 0 { lineRef = 0 }
    }

    /// Runs the line's own physics: pinned to the anchor and the spinnerets
    /// while it is in use, left to drift down from the anchor once let go.
    private func updateRope(dt: CGFloat) {
        let attach = silkAttachWorld()
        var head: V2?
        if webActive {
            head = webAnchor
            webAlpha.stiffness = 120
            webAlpha.damping = 16
            let d = webAnchor.distance(to: attach)
            // Taut under its weight; on the pointer, the line keeps its length
            // and goes slack when it is lifted toward the anchor.
            rope.length = mode == .held ? max(webLen, d) : d * 1.004
            rope.tailPinned = true
        } else if let from = buildThreadFrom {
            // Silk being laid for the hammock: from where it was last stuck
            // down to the spinnerets, with a little slack so it drapes.
            head = from
            webAlpha.stiffness = 120
            webAlpha.damping = 16
            rope.length = from.distance(to: attach) * 1.012 + 2
            rope.tailPinned = true
        } else if let shot = airShot, shot.progress > 0 {
            let tip = V2.lerp(attach, shot.target, easeOutCubic(shot.progress))
            head = tip
            rope.length = tip.distance(to: attach) * 1.01
            rope.tailPinned = true
        } else if mode == .attached, activity == .shoot {
            let tip = V2.lerp(attach, shotTarget, easeOutCubic(shotProgress))
            head = tip
            rope.length = tip.distance(to: attach) * 1.01
            rope.tailPinned = true
        } else if webAlpha.value > 0.01, rope.live {
            // Let go: the free end drifts down from the anchor as it fades.
            head = rope.head
            rope.tailPinned = false
        }
        guard let h = head else {
            if rope.live { rope.clear() }
            return
        }
        if !rope.live || h.distance(to: rope.head) > 90 {
            rope.reset(from: h, to: attach)
        }
        let g: CGFloat = rope.tailPinned ? 700 : 260
        // A wind bows the line out.
        let wind = weatherOnIt && !sheltered ? V2(windPush * 0.8, 0) : .zero
        rope.step(head: h, tail: attach, gravity: g, drag: rope.tailPinned ? 0.975 : 0.985, wind: wind, dt: dt)
    }

    /// The sprite's yaw. During a turn it sweeps from one profile to the other
    /// on a cosine, dwelling for a moment at the front view; otherwise it
    /// settles onto whichever way the body is logically facing. The legs are
    /// mirrored and re-paired at the exact moment it passes the front view,
    /// where the layout is symmetric, so no foot ever jumps.
    private func updateYaw(dt: CGFloat) {
        let before = yaw
        if mode == .attached && activity == .turn {
            let u = smoothstep(activityTime / max(activityDur, 0.01))
            // From however far round it already was, through the front
            // view, out to the full opposite profile — so a turn begun
            // face on (after a greeting, say) does not snap to profile first.
            let sign: CGFloat = turnFromYaw >= 0 ? 1 : -1
            yaw = u < 0.5 ? turnFromYaw * cos(u * .pi) : sign * cos(u * .pi)
            if (yaw < 0) != (turnFromYaw < 0) && facing != pendingDir {
                facing = pendingDir
                walkDir = pendingDir
                turned = true
                faced()
            }
        } else if mode == .dangling {
            // On a line it is seen side on the whole time: head straight
            // down under the rest of it (or straight up, climbing), as a
            // spider hanging from its spinnerets is. Turned toward you, the
            // face-on layout would put its head beside its abdomen.
            yaw = approach(yaw, facing, 9, dt)
        } else if mode == .nesting {
            yaw = approach(yaw, facing, 6, dt)
        } else if mode == .airborne, airShot != nil || draglineCatchY != nil {
            // Side on for the shot and the line, so the twist reads.
            yaw = approach(yaw, facing, 12, dt)
        } else if mode == .attached && activity == .groove {
            // Dancing side on — or turned square on to you to throw its arms
            // up, as in a greeting (see `grooveLeg`).
            yawSpring(to: grooveMove == .arms && !grooveEnding ? facing * 0.1 : facing, dt: dt)
        } else if mode == .attached && (activity == .greet || activity == .stare
                                        || (liftsOuterPair && (activity == .armsUp || activity == .curious))) {
            // (A two-legged gesture begun face on stays face on: the legs it
            // raised are the ones either side of its face.)
            // Square on to you, all but the whole way round to the front
            // view — not right on it, where the spring's overshoot would
            // tip it over into the mirror image and back. (Staring at the
            // pointer, on whichever side of the front view it is.)
            let side = activity == .stare && interest > 0.5 ? interestSide : facing
            yawSpring(to: side * 0.1, dt: dt)
        } else {
            // A glance turns it part-way toward you without changing which
            // way it faces along the ledge. (Only on a ledge: a glance it
            // was in the middle of when it was picked up does not follow
            // it into the air.) So does walking turned round to you, and
            // the looks round at you it gives where it stands (see "Body
            // language").
            let g = activity == .glance ? glanceDepth : (mode == .attached ? max(glance, worn.turn, beatTurn) : 0)
            var target = facing * (1 - g)
            // Interested, it turns toward the pointer instead — the whole
            // way round if need be, on the same spring. Not on the move,
            // though: going somewhere it comes three-quarters round at most
            // (see `updateInterest`), and never swings on round past the
            // front view to set off back the way it came the moment it has
            // turned to go — or walk on with its body turned backwards.
            // For a proper look it stops first.
            if mode == .attached {
                let onTheMove = speed > 1 || [.walk, .sneak, .scurry].contains(activity)
                let toward = onTheMove ? facing * max(facing * interestYawTarget, 0.4) : interestYawTarget
                target = lerp(target, toward, interest)
            }
            // (A double take's snap round is quicker than any turn.)
            if yawSnap {
                yawVel += ((target - yaw) * 520 - yawVel * 40) * dt
                yaw = clamp(yaw + yawVel * dt, -1, 1)
            } else {
                yawSpring(to: target, dt: dt)
            }
        }
        if mode != .attached || activity == .turn { yawVel = 0 }
        if (yaw >= 0) != (before >= 0) {
            // Come round past the front view after the pointer, not in a
            // turn: it now faces the other way along the ledge, and stays
            // that way when the pointer leaves.
            if mode == .attached, activity != .turn {
                let was = facing
                facing = yaw >= 0 ? 1 : -1
                // On the move, going the other way starts from a stop — its
                // feet come down where they are — not a reversal in a frame.
                if walkDir != facing { speed = 0 }
                walkDir = facing
                if facing != was { faced() }
            }
            for i in legs.indices {
                legs[i].foot.x = -legs[i].foot.x
                legs[i].footVel.x = -legs[i].footVel.x
                legs[i].swingFrom.x = -legs[i].swingFrom.x
            }
            // Re-pair: the foot that was at leg i's spot is now at leg 7-i's.
            // Only the moving state changes hands — each slot keeps its own
            // hip, rest pose and gait phase.
            for i in 0..<4 {
                let j = 7 - i
                var a = legs[i], b = legs[j]
                (a.foot, b.foot) = (b.foot, a.foot)
                (a.footVel, b.footVel) = (b.footVel, a.footVel)
                (a.swingFrom, b.swingFrom) = (b.swingFrom, a.swingFrom)
                (a.swinging, b.swinging) = (b.swinging, a.swinging)
                (a.lift, b.lift) = (b.lift, a.lift)
                (a.settle, b.settle) = (b.settle, a.settle)
                a.settleTo.x = -a.settleTo.x; b.settleTo.x = -b.settleTo.x
                (a.settleTo, b.settleTo) = (b.settleTo, a.settleTo)
                (a.skipSwing, b.skipSwing) = (b.skipSwing, a.skipSwing)
                (a.swingPh0, b.swingPh0) = (b.swingPh0, a.swingPh0)
                (a.swingShift, b.swingShift) = (b.swingShift, a.swingShift)
                (a.swingDir, b.swingDir) = (-b.swingDir, -a.swingDir)
                (a.swingU, b.swingU) = (b.swingU, a.swingU)
                a.swingTo.x = -a.swingTo.x; b.swingTo.x = -b.swingTo.x
                (a.swingTo, b.swingTo) = (b.swingTo, a.swingTo)
                (a.stepDur, b.stepDur) = (b.stepDur, a.stepDur)
                (a.landedAt, b.landedAt) = (b.landedAt, a.landedAt)
                if refGiveNow.count == legs.count { refGiveNow.swapAt(i, j) }
                // Walking, a step in flight carries on as it was going, on
                // its own clock: the twin slot's place in the gait is a few
                // hundredths of a cycle off, which would jerk it on or cut it
                // short in mid-air.
                if mode == .attached, legController == .gait {
                    // (The refined walk counts its places in the gait the
                    // other way round: see `refStart`.)
                    var d = a.phase - b.phase
                    if refinedWalk {
                        d = (refStart(j) - refStart(i)).truncatingRemainder(dividingBy: 1)
                        if d > 0.5 { d -= 1 } else if d < -0.5 { d += 1 }
                    }
                    if a.swinging { a.swingPh0 += d; a.swingShift += d }
                    if b.swinging { b.swingPh0 -= d; b.swingShift -= d }
                }
                legs[i] = a
                legs[j] = b
                if footWorld.count == legs.count, footWorldVel.count == legs.count {
                    footWorld.swapAt(i, j)
                    footWorldVel.swapAt(i, j)
                }
                if kneeWorld.count == legs.count, kneeWorldVel.count == legs.count {
                    kneeWorld.swapAt(i, j)
                    kneeWorldVel.swapAt(i, j)
                }
                // A mirrored knee bends the other way round its line.
                if kneeShape.count == legs.count {
                    let (ki, kj) = (kneeShape[i], kneeShape[j])
                    kneeShape[i] = V2(kj.x, -kj.y)
                    kneeShape[j] = V2(ki.x, -ki.y)
                }
                if kneeShapeVel.count == legs.count {
                    let (vi, vj) = (kneeShapeVel[i], kneeShapeVel[j])
                    kneeShapeVel[i] = V2(vj.x, -vj.y)
                    kneeShapeVel[j] = V2(vi.x, -vi.y)
                }
                kneeOver.swapAt(i, j)
                kneeOverAim.swapAt(i, j)
                // (And the dance's hold on each foot.)
                grooveAir.swapAt(i, j)
                groovePlanted.swapAt(i, j)
                (grooveBase[i], grooveBase[j]) = (V2(-grooveBase[j].x, grooveBase[j].y), V2(-grooveBase[i].x, grooveBase[i].y))
                (grooveAirAt[i], grooveAirAt[j]) = (V2(-grooveAirAt[j].x, grooveAirAt[j].y), V2(-grooveAirAt[i].x, grooveAirAt[i].y))
                // (On a line likewise: the side of its leg a knee is on.)
                if lineSide.count == legs.count {
                    (lineSide[i], lineSide[j]) = (-lineSide[j], -lineSide[i])
                    (lineSideAim[i], lineSideAim[j]) = (-lineSideAim[j], -lineSideAim[i])
                    (lineSideVel[i], lineSideVel[j]) = (-lineSideVel[j], -lineSideVel[i])
                    lineBoneLen.swapAt(i, j)
                }
            }
        }
    }

    private var mirrorSign: CGFloat { yaw >= 0 ? 1 : -1 }

    /// The upper body's turn on the legs. Taken with the pointer, head and
    /// abdomen swing round to it first, quickly, and the legs come round
    /// after, a step at a time (see `watchingPlanted`); as they catch up
    /// the upper body comes back square on them. Otherwise it is straight
    /// on the legs — and while turning round, rolling or off the ledge it
    /// goes back there.
    private func updateHeadTurn(dt: CGFloat) {
        let legsTurned = yaw - yawBefore
        yawStillFor = dt > 0 && abs(legsTurned) / dt < 0.08 ? yawStillFor + dt : 0
        yawBefore = yaw
        let free = mode == .attached && activity != .turn && activity != .roll && activity != .groove && ball < 0.01
        // Following the pointer, the upper body stays on it while the legs
        // shift round underneath: it is not carried along with them.
        if free { headTurn -= legsTurned * interest }
        let most = Spider.maxHeadTurn
        // (Its own looks round at you — walking with its head and abdomen
        // turned to watch you, looking about, a shake of the head — give
        // way to the pointer's.)
        let own = (worn.look + beatLook) * (1 - interest) + shakeNow.turn
        let wish = free ? (headYawTarget - yaw) * interest - mirrorSign * own : 0
        let want = clamp(wish, -most, most)
        headTurnVel += ((want - headTurn) * 240 - headTurnVel * 28) * dt
        headTurn += headTurnVel * dt
        var lo = max(-most, -1 - yaw), hi = min(most, 1 - yaw)
        // (Dressed in something lopsided face on, the head and abdomen stay
        // on the legs' side of the front view, where it would flip over.)
        if symmetricLook?.look != look { symmetricLook = (look, SpiderRenderer.faceOnSymmetric(look)) }
        if symmetricLook?.symmetric == false {
            if yaw >= 0 { lo = max(lo, -yaw) } else { hi = min(hi, -yaw - 0.0001) }
        }
        // Turned as far as it goes from the legs, and wanting further.
        headPinnedFor = free && interest > 0.3 && (wish > hi + 0.1 || wish < lo - 0.1) ? headPinnedFor + dt : 0
        if headTurn < lo || headTurn > hi {
            headTurn = clamp(headTurn, lo, hi)
            headTurnVel = 0
        }
        if want == 0, abs(headTurn) < 0.0005, abs(headTurnVel) < 0.005 { headTurn = 0; headTurnVel = 0 }
    }

    /// The body comes round toward or away from you on a spring — a
    /// movement with a start and a finish — rather than the snap-and-settle
    /// of a plain exponential.
    private var yawVel: CGFloat = 0
    private func yawSpring(to target: CGFloat, dt: CGFloat) {
        yawVel += ((target - yaw) * 120 - yawVel * 19) * dt
        yaw = clamp(yaw + yawVel * dt, -1, 1)
    }

    /// Sprite-local units to world points, and back.
    private func toWorld(_ l: V2) -> V2 {
        pos + V2(l.x * mirrorSign, l.y).rotated(by: heading) * config.scale
    }

    private func toLocal(_ w: V2) -> V2 {
        var v = ((w - pos) / max(config.scale, 0.05)).rotated(by: -heading)
        v.x *= mirrorSign
        return v
    }

    /// A world direction in sprite space.
    private func toLocalDir(_ w: V2) -> V2 {
        var v = w.rotated(by: -heading)
        v.x *= mirrorSign
        return v
    }

    /// Puts a foot on the actual edge it is standing on. This is what keeps
    /// the feet on a window as the body swings round its corner: the flat
    /// ground line in the sprite's own frame is only right in the middle of
    /// an edge.
    /// `spread`: for where a foot is going to stand (a step, a stance, a
    /// pose) rather than one already down: see `spreadOnEdge`.
    private func groundFoot(_ local: V2, spread: Bool = false) -> V2 {
        groundSpot(local, spread: spread).point
    }

    /// `groundFoot`, and whether there is really something there to stand
    /// on: false when the only edge near enough is hidden behind a window in
    /// front of it.
    private func groundSpot(_ local: V2, spread: Bool = false) -> (point: V2, seen: Bool) {
        if mode == .nesting, let h = hammock {
            // On the silk: the sling's centre line is the ground.
            return (toLocal(h.nearest(to: toWorld(local))), true)
        }
        guard mode == .attached, let loop = map.loop(anchor.loopID), !loop.edge.isEmpty else { return (local, true) }
        let want = toWorld(local)
        // How far from where a foot would naturally be another surface can
        // take it: a step across to the window alongside, not a long
        // strained reach for one further off.
        let reach = 11 * config.scale
        // Its own edge, first: the nearest point on it — or, for a foot out
        // past a corner, that far round the corner (see `footOnEdge`).
        // (Spread by the body's own axis only once the body is lined up with
        // the way the surface runs — walking, or rounding a corner. Still
        // swinging down onto it out of a landing, the axis says nothing
        // about where the surface goes.)
        let aligned = abs(angleDelta(heading, headingTarget)) < 0.3
        var own = footOnEdge(want, loop)
        if spread && aligned {
            // Spreading only ever moves a foot a little further round a
            // corner than the nearest point would; one that lands a long
            // way off has been walked round the wrong way (the body right
            // on a corner, where the edge under it is ambiguous), and the
            // nearest point is the better answer.
            let s = spreadOnEdge(local, loop)
            if s.point.distance(to: own.point) < 12 * config.scale { own = s }
        }
        var best = own.point
        var bestCost = want.distance(to: own.point)
        if !own.visible { bestCost = .greatestFiniteMagnitude }
        // Then any other edge a foot could be on: the window next to it, the
        // one in front whose side it has walked up to. A foot goes where
        // there is really something under it — half on one window and half
        // on the next, if that is how it is standing — with its own edge
        // preferred when the two are much of a muchness.
        if bestCost > 1.5 {
            for other in map.loops where other.id != loop.id && !other.edge.isEmpty {
                if other.kind.onWindow, other.rect.insetBy(dx: -reach - 40, dy: -reach - 40).contains(want.point) == false { continue }
                let o = footOnEdge(want, other, wrap: false)
                guard o.visible else { continue }
                let cost = want.distance(to: o.point) + 3 * config.scale
                if cost < bestCost, cost < reach { best = o.point; bestCost = cost }
            }
        }
        return (toLocal(best), bestCost < .greatestFiniteMagnitude)
    }

    /// Where a foot is to stand, by how far along the body it is: that far
    /// along the surface from under the body, round a corner if there is
    /// one. On a straight edge that is simply the point under it; round a
    /// corner — the body half-way round and the rest pose squeezed up
    /// against the next side — the feet keep their spacing, wrapped round
    /// the corner, instead of crowding together where the pose's points
    /// happen to land.
    private func spreadOnEdge(_ local: V2, _ loop: SurfaceLoop) -> (point: V2, visible: Bool) {
        let under = toWorld(V2(0, SpiderRenderer.ground))
        var base = (seg: 0, t: CGFloat(0), d: CGFloat.greatestFiniteMagnitude)
        for (i, e) in loop.edge.enumerated() {
            let (t, d) = projectOnSegment(under, e.a, e.b)
            if d < base.d { base = (i, t, d) }
        }
        let n = loop.edge.count
        // Which way along the edge the body's +x runs.
        let forward = toWorld(V2(1, SpiderRenderer.ground)) - under
        var dist = local.x * config.scale * (forward.dot(loop.edge[base.seg].dir) >= 0 ? 1 : -1)
        var i = base.seg, t = base.t
        for _ in 0..<(n + 2) {
            let e = loop.edge[i]
            let room = dist >= 0 ? e.len - t : -t
            if abs(dist) <= abs(room) { t += dist; dist = 0; break }
            dist -= room
            let next = dist >= 0 ? i + 1 : i - 1
            if next < 0 || next >= n {
                guard loop.closed else { t = dist >= 0 ? e.len : 0; dist = 0; break }
            }
            i = (next + n) % n
            t = dist >= 0 ? 0 : loop.edge[i].len
        }
        let e = loop.edge[i]
        var point = e.point(at: clamp(t, 0, e.len))
        var normal = e.normal
        // A window's corner is rounded: near one, the foot goes on the curve.
        if let c = loop.onRoundedCorner(point) { point = c.point; normal = c.normal }
        let visible = !loop.kind.onWindow || map.isVisible(point + normal * 3, depth: loop.depth)
        return (point, visible)
    }

    /// Where a foot aimed at `p` goes on a loop's edge, and whether that
    /// spot can be seen (not behind a window in front of that loop). The
    /// nearest point — except that everything out past a corner has the
    /// corner itself as its nearest point, and a spider's feet do not all
    /// pile onto a corner: a foot overshooting the corner goes that far
    /// round it, onto the next side, so they spread down it as a spider's
    /// grip round a corner does. A foot already on an edge is left exactly
    /// where it is, so a planted foot never creeps.
    private func footOnEdge(_ p: V2, _ loop: SurfaceLoop, wrap: Bool = true) -> (point: V2, visible: Bool) {
        var best = (seg: 0, t: CGFloat(0), d: CGFloat.greatestFiniteMagnitude)
        for (i, s) in loop.edge.enumerated() {
            let (t, d) = projectOnSegment(p, s.a, s.b)
            if d < best.d { best = (i, t, d) }
        }
        let seg = loop.edge[best.seg]
        var point = seg.point(at: best.t)
        var normal = seg.normal
        let atEnd = best.t < 0.01 || best.t > seg.len - 0.01
        if wrap, atEnd, best.d > 1 {
            // Out past a corner. Round it onto whichever side meets there
            // and faces the way the foot is, by the distance it overshot.
            let v = point
            let away = (p - v).normalized
            var onto: (seg: Seg, fromA: Bool, fit: CGFloat)?
            for s in loop.edge where s.len > 0.5 {
                let fromA = s.a.distance(to: v) < 0.5
                guard fromA || s.b.distance(to: v) < 0.5 else { continue }
                let fit = s.normal.dot(away)
                if onto == nil || fit > onto!.fit { onto = (s, fromA, fit) }
            }
            if let o = onto, o.fit > 0.2 {
                let e = min(best.d, o.seg.len)
                point = o.fromA ? o.seg.point(at: e) : o.seg.point(at: o.seg.len - e)
                normal = o.seg.normal
            }
        }
        // A window's corner is rounded: near one, the foot goes on the curve,
        // not out on the square corner where there is no window at all.
        if let c = loop.onRoundedCorner(point) { point = c.point; normal = c.normal }
        // The screen's rim, the menu bar and the Dock are in front of every
        // window; a window's edge can be behind another window.
        let visible = !loop.kind.onWindow || map.isVisible(point + normal * 3, depth: loop.depth)
        return (point, visible)
    }

    /// Asleep, its feet are drawn in under it, tucked against where the
    /// edge would be if it were flat — which, asleep on a window's corner,
    /// is nowhere near it: they would hang in the air. Each goes onto the
    /// edge where it really is under it instead, wrapped round the corner,
    /// tucked in by as much. (By how far the edge is off where the pose
    /// takes it to be — the flat line, as far under the body as it has
    /// let itself down onto it — so on a straight edge this is the pose
    /// exactly.)
    private func sleepFoot(_ i: Int, _ tuck: V2) -> V2 {
        guard mode == .attached else { return tuck }
        let flat = V2(tuck.x, SpiderRenderer.ground - refRide / max(config.scale, 0.05))
        let off = groundFoot(flat, spread: true, leg: i) - flat
        let w = clamp((off.length - 0.3) / 1.2, 0, 1)
        return w > 0 ? tuck + off * w : tuck
    }

    /// Puts a posed foot that is meant to be standing onto the real
    /// surface. Gesture poses are laid out against the sprite's flat
    /// ground line, which is not where the edge is round a corner, seen
    /// front on looking at the pointer, or with the body lifted up on its
    /// toes for a wave: the feet would hang in the air beside it. A foot
    /// the pose leaves on the ground line goes onto the edge itself, so
    /// the legs flex under the body instead of floating with it; a foot
    /// the pose raises or tucks is left as it is, relative to the body.
    private func groundPose(_ i: Int, _ target: V2) -> V2 {
        guard mode == .attached, target.y <= legs[i].rest.y + 1.5 else { return target }
        return groundFoot(target, spread: true, leg: i)
    }

    /// `groundFoot` for leg `i`, kept to where that leg can reach. On a
    /// straight edge the ground is right where the pose puts the foot and
    /// this is `groundFoot` exactly. Round a corner, at the lip of a step,
    /// over a crack or with a second surface close by, the nearest ground
    /// can be a long way off — the far side of a gap, the top of the next
    /// block, an edge beyond the one it stands on — and a leg sent there
    /// is drawn out to two or three times its length. There, it goes to
    /// the nearest bit of ground it can reach instead: never further from
    /// its hip than the pose itself asked for (with a little slack for the
    /// body riding up and down on its legs), or than the leg is long.
    private func groundFoot(_ local: V2, spread: Bool = false, leg i: Int) -> V2 {
        reachableSpot(local, spread: spread, leg: i).point
    }

    /// `groundFoot(_:spread:leg:)`, and whether the spot is on the ground:
    /// false when there is none in reach and the leg is only reaching out
    /// toward it.
    private func reachableSpot(_ local: V2, spread: Bool = false, leg i: Int) -> (point: V2, onGround: Bool) {
        var (p, seen) = groundSpot(local, spread: spread)
        guard mode == .attached else { return (p, true) }
        let hip = SpiderRenderer.rig(i, profile: SpiderRenderer.profileAmount(yaw: yaw), look: look).hip
        // Round a corner, the leg keeps the span it has along a ledge.
        if spread, let q = cornerFoothold(i, local, hip: hip, flat: p) { p = q; seen = true }
        let most = max(local.distance(to: hip) + Spider.reachSlack, legLength(i) * Spider.reachShare)
        // (Likewise a spot on an edge hidden behind a window in front: there
        // is nothing there it could be seen to stand on.)
        guard p.distance(to: hip) > most || !seen else { return (p, true) }
        if let q = nearestReachable(local, hip: hip, within: most) { return (q, true) }
        // No ground in reach at all — the body out over a gap it is
        // stepping across, or not yet down onto the ledge — and the leg
        // reaches out toward the nearest, as far as it goes.
        let d = p.distance(to: hip)
        return d <= most ? (p, true) : (hip + (p - hip) * (most / d), false)
    }

    /// Where a foot aimed at `local` stands round a corner: the leg swings
    /// about its hip — keeping the span it would have along a ledge, from the
    /// hip to the line the body stands over — until the foot meets the
    /// ground. Spread round the corner by how far along the body it is (as
    /// `flat`, the spot `groundSpot` found, is), a foot over the outside of
    /// one lands well out from its hip — the leg drawn out long and
    /// straight, the body up on its toes — and one into an inside corner
    /// lands right under its hip, folded up tight. Eased in as the ground
    /// under the foot turns away from that line or falls away from it, so
    /// on a straight edge — where `flat` is the very spot — this is nil, and
    /// nothing changes.
    private func cornerFoothold(_ i: Int, _ local: V2, hip: V2, flat p: V2) -> V2? {
        guard mode == .attached, let loop = map.loop(anchor.loopID), !loop.edge.isEmpty,
              abs(angleDelta(heading, headingTarget)) < 0.3 else { return nil }
        let s = max(config.scale, 0.05)
        // On a ledge the foot would be on the line the body stands over, as
        // far under it as it is riding.
        let line = V2(local.x, SpiderRenderer.ground - refRide / s)
        // (Only a leg that would be drawn out, and by as much as it would:
        // one folded up closer in — into an inside corner — stands folded,
        // as a spider's legs do there.)
        let span = line.distance(to: hip), long = p.distance(to: hip) - span
        guard long > 0 else { return nil }
        let off = max(abs(surfaceSide(toWorld(line), loop)) / s, p.distance(to: line))
        let w = max(smoothstep(clamp((edgeTurn(under: p) - 0.04) / 0.2, 0, 1)), smoothstep(clamp((off - 1) / 4, 0, 1)))
            * smoothstep(clamp(long / (span * 0.12 + 1), 0, 1))
        let r = SpiderRenderer.rig(i, profile: SpiderRenderer.profileAmount(yaw: yaw), look: look)
        guard w > 0, let q = swingToGround(hip: hip, toward: line, span: span,
                                           out: r.foot.x >= r.hip.x ? 1 : -1, loop) else { return nil }
        return w >= 1 ? q : refGroundNear(V2.lerp(p, q, w)).point
    }

    /// A leg `span` long (sprite units) swung about `hip` from pointing at
    /// `toward` round to where its foot first meets the ground of `loop`,
    /// whichever way round that is the least turn — out in the open, where
    /// it can be seen, and never round past its own hip to the far side of
    /// it (`out`: +1 for a leg whose foot stands out ahead of its hip, -1
    /// behind), where its knee would have to bend the wrong way. Nil if no
    /// ground is in reach within a good way round.
    private func swingToGround(hip: V2, toward: V2, span: CGFloat, out: CGFloat? = nil, _ loop: SurfaceLoop) -> V2? {
        guard span > 1 else { return nil }
        let s = max(config.scale, 0.05)
        let h = toWorld(hip), r = span * s
        let a0 = (toWorld(toward) - h).angle
        // (Only the ground near enough to matter: a long loop is mostly far off.)
        let near = loop.edge.indices.filter { projectOnSegment(h, loop.edge[$0].a, loop.edge[$0].b).dist < r + 4 * s }
        guard !near.isEmpty else { return nil }
        func side(_ a: CGFloat) -> CGFloat { surfaceSide(h + V2.angle(a) * r, loop, edges: near) }
        // (On its own side of its hip: no further across under it than
        // where it was pointing, or than `refCross` of the span.)
        let least = out.map { min((toward - hip).x * $0, 0) - span * Spider.refCross } ?? 0
        func ownSide(_ a: CGFloat) -> Bool {
            guard let out else { return true }
            return (toLocal(h + V2.angle(a) * r) - hip).x * out >= least
        }
        let f0 = side(a0)
        var found: CGFloat?
        if abs(f0) < 0.01 * s {
            found = a0
        } else {
            // Out from where it points, a step at a time either way, to the
            // first place the foot goes from the open to the ground or back:
            // the nearer of the two — though not one the far side of its hip
            // if the other is not.
            let step = 2 * CGFloat.pi / 180
            var first: [CGFloat?] = [nil, nil]
            for (j, way) in [CGFloat(1), -1].enumerated() {
                var last = f0
                var k = 1
                while CGFloat(k) * step <= Spider.cornerSwingMost {
                    let a = a0 + way * CGFloat(k) * step
                    let f = side(a)
                    if (f >= 0) != (last >= 0) {
                        var lo = a - way * step, hi = a, flo = last
                        for _ in 0..<14 {
                            let mid = (lo + hi) / 2, fm = side(mid)
                            if (fm >= 0) == (flo >= 0) { lo = mid; flo = fm } else { hi = mid }
                        }
                        first[j] = (lo + hi) / 2
                        break
                    }
                    last = f
                    k += 1
                }
            }
            let ways = first.compactMap { $0 }.sorted { abs($0 - a0) < abs($1 - a0) }
            found = ways.first(where: ownSide) ?? ways.first
        }
        let q: V2
        if let a = found {
            q = refGroundNear(toLocal(h + V2.angle(a) * r)).point
        } else if f0 > 0, side(a0 + .pi) > 0 {
            // (The ground falls away under it — over the outside of a
            // window's rounded corner, under the hip of a short leg — and it
            // is not long enough to reach it as it stands: it reaches down to
            // the nearest of it, a little further out than that.)
            let e: CGFloat = 0.5
            let g = V2(surfaceSide(h + V2(e, 0), loop, edges: near) - surfaceSide(h - V2(e, 0), loop, edges: near),
                       surfaceSide(h + V2(0, e), loop, edges: near) - surfaceSide(h - V2(0, e), loop, edges: near))
            guard g.length > 1e-6 else { return nil }
            q = refGroundNear(toLocal(h - g.normalized * surfaceSide(h, loop, edges: near))).point
            guard q.distance(to: hip) < span * 1.25 else { return nil }
        } else {
            return nil
        }
        // (Not somewhere behind a window in front: nothing there to stand on.)
        if loop.kind.onWindow {
            let qw = toWorld(q), e: CGFloat = 0.5
            let n = V2(surfaceSide(qw + V2(e, 0), loop, edges: near) - surfaceSide(qw - V2(e, 0), loop, edges: near),
                       surfaceSide(qw + V2(0, e), loop, edges: near) - surfaceSide(qw - V2(0, e), loop, edges: near))
            if n.length > 1e-6, !map.isVisible(qw + n.normalized * 3, depth: loop.depth) { return nil }
        }
        return q
    }
    /// The furthest round a leg is swung, either way, for its foot to find
    /// the ground round a corner.
    private static let cornerSwingMost: CGFloat = 100 * .pi / 180

    /// How far `w` (world) is out from the ground of `loop`: more than 0 out
    /// in the open, less inside the thing it stands on (or past the rim of
    /// the screen). A window's corners are rounded. `edges`: only these of
    /// its edges.
    private func surfaceSide(_ w: V2, _ loop: SurfaceLoop, edges: [Int]? = nil) -> CGFloat {
        if loop.kind == .windowEdge, loop.cornerRadius > 0.5, loop.closed {
            let r = loop.rect
            let R = min(loop.cornerRadius, r.width / 2, r.height / 2)
            let qx = abs(w.x - r.midX) - (r.width / 2 - R), qy = abs(w.y - r.midY) - (r.height / 2 - R)
            return V2(max(qx, 0), max(qy, 0)).length + min(max(qx, qy), 0) - R
        }
        var best = (d: CGFloat.greatestFiniteMagnitude, out: CGFloat(1))
        for k in edges ?? Array(loop.edge.indices) {
            let e = loop.edge[k]
            guard e.len > 0.01 else { continue }
            let (t, d) = projectOnSegment(w, e.a, e.b)
            guard d < best.d - 1e-9 else { continue }
            var n = e.normal
            if t < 0.01 || t > e.len - 0.01 {
                // At a corner: out is the way both edges meeting there face.
                let v = t < 0.01 ? e.a : e.b
                var sum = V2.zero
                for f in loop.edge where f.len > 0.01 && (f.a.distance(to: v) < 0.5 || f.b.distance(to: v) < 0.5) { sum += f.normal }
                if sum.length > 0.01 { n = sum.normalized }
            }
            best = (d, (w - e.point(at: t)).dot(n) >= 0 ? 1 : -1)
        }
        return best.d * best.out
    }

    /// Past what the pose asks for, how much further a foot may be put on
    /// the ground — what the body's bob and lift can add — and how much of
    /// a leg's full length it may reach out to when the pose is closer in.
    private static let reachSlack: CGFloat = 6
    private static let reachShare: CGFloat = 0.94
    /// How far behind its hip — or behind where its stride takes it, if
    /// that is further — a front foot can be left, walking, before it
    /// steps forward out of turn. (An ordinary stride trails it about half
    /// this.)
    private static let strandedBehind: CGFloat = 18

    /// Standing about taken with the pointer, it follows it round with its
    /// feet planted: a foot holds its place on the ledge while the body
    /// turns over it, and only steps — one at a time — once it has been
    /// left well off the spot this way of standing wants it on, rather
    /// than every foot sliding round with the body.
    private var watchingPlanted: Bool {
        mode == .attached && speed <= 1 && !absorbingLanding
            && (interest > 0.05 && Spider.watchStances.contains(activity) || turningToYou)
    }
    /// Coming round to look at you where it stands — stopped on its way,
    /// a double take, a shake of the head — its feet stay where they are
    /// and step round after it, the same way.
    private var turningToYou: Bool {
        (activity == .walk && checkIn != nil) || activity == .doubleTake || shakeNow.on > 0
            || (Spider.onFoot.contains(activity) && (max(worn.turn, beatTurn) > 0.05 || worn.look > 0.05))
    }
    private static let watchStances: Set<Activity> = [.idle, .look, .rest, .stare, .glance, .peer]
    /// How far off its spot, in sprite units, a planted foot is left before
    /// it steps (turning from side on to face on moves the spots up to ~9)
    /// while the body is coming round; and, once it has stopped turning for
    /// `settledAfter` seconds, how near it tidies its feet up to.
    private static let plantSlack: CGFloat = 6
    private static let plantTidy: CGFloat = 2.5
    private static let settledAfter: CGFloat = 0.35
    /// How long the body's yaw has been all but still.
    private var yawStillFor: CGFloat = 0
    private var yawBefore: CGFloat = 1

    /// A planted foot, watching the pointer (see `watchingPlanted`): it
    /// stays where it is on the ledge — the caller has already held it
    /// there against the body's motion — unless it is left more than
    /// `plantSlack` off `target`, when it steps there. Returns false for a
    /// foot this does not look after (one up in the air).
    private func keepPlanted(_ leg: inout Leg, _ i: Int, to target: V2, dt: CGFloat) -> Bool {
        if leg.settle >= 0 { return settleFoot(&leg, i, to: target, dt: dt) }
        guard leg.foot.y <= max(target.y, leg.hip.y) + 5 else { return false }
        // (Nor is a foot still on its way down — a walk stopped mid-stride
        // — held up in the air: down it comes first.)
        if !Spider.debugNoBodyLanguage, leg.foot.distance(to: groundFoot(leg.foot)) > 1.5 { return false }
        let off = leg.foot.distance(to: target)
        // (One at a time, unless it is badly out of place.)
        let busy = legs.indices.contains { $0 != i && legs[$0].settle >= 0 }
        let slack = yawStillFor > Spider.settledAfter ? Spider.plantTidy : Spider.plantSlack
        if off > slack, !busy || off > Spider.plantSlack * 2, target.distance(to: leg.rest) < 22 {
            leg.settle = 0
            leg.swingFrom = leg.foot
            leg.settleTo = target
            return settleFoot(&leg, i, to: target, dt: dt)
        }
        leg.footVel = .zero
        leg.lift = approach(leg.lift, 0, 16, dt)
        return true
    }

    /// Thigh and shin together, in sprite units, as the leg is drawn now.
    private func legLength(_ i: Int) -> CGFloat {
        let r = SpiderRenderer.rig(i, profile: SpiderRenderer.profileAmount(yaw: yaw), look: look)
        return (r.knee - r.hip).length + (r.foot - r.knee).length
    }

    /// The spot on the ground nearest `want` that is within `most` of the
    /// hip (all sprite units): on the edge it stands on, or on another one
    /// close by — on a window's rounded corner where there is one, and
    /// never somewhere hidden behind a window in front. Nil if there is no
    /// ground in reach at all.
    private func nearestReachable(_ want: V2, hip: V2, within most: CGFloat) -> V2? {
        guard let own = map.loop(anchor.loopID) else { return nil }
        let s = config.scale
        let wantW = toWorld(want), hipW = toWorld(hip), r = most * s
        var best: V2?
        var bestCost = CGFloat.greatestFiniteMagnitude
        for loop in [own] + map.loops.filter({ $0.id != own.id }) {
            if loop.id != own.id, loop.kind.onWindow, !loop.rect.insetBy(dx: -r, dy: -r).contains(hipW.point) { continue }
            // A step across to another surface costs a little: its own
            // edge is preferred when the two are much of a muchness.
            let penalty: CGFloat = loop.id == own.id ? 0 : 3 * s
            for e in loop.edge where e.len > 0.01 {
                // The stretch of this edge inside the reach.
                let f = e.a - hipW
                let bq = f.dot(e.dir), c = f.lengthSquared - r * r
                let disc = bq * bq - c
                guard disc > 0 else { continue }
                let root = disc.squareRoot()
                let t0 = max(-bq - root, 0), t1 = min(-bq + root, e.len)
                guard t1 > t0 else { continue }
                // Its nearest point to where the pose wanted the foot, and a
                // few more along it, each put on a rounded corner if near one.
                let tn = clamp((wantW - e.a).dot(e.dir), t0, t1)
                for k in 0...8 {
                    let tk = k == 8 ? tn : lerp(t0, t1, CGFloat(k) / 7)
                    var q = e.point(at: tk)
                    var normal = e.normal
                    if let c = loop.onRoundedCorner(q) { q = c.point; normal = c.normal }
                    guard q.distance(to: hipW) <= r * 1.02 else { continue }
                    if loop.kind.onWindow, !map.isVisible(q + normal * 3, depth: loop.depth) { continue }
                    let cost = q.distance(to: wantW) + penalty
                    if cost < bestCost { best = q; bestCost = cost }
                }
            }
        }
        return best.map { toLocal($0) }
    }

    private func trackCursorMotion(dt: CGFloat) {
        let d = cursor - prevCursor
        prevCursor = cursor
        if dt > 0 { cursorVel = approach(cursorVel, d / dt, 18, dt) }
        cursorStillFor = cursorVel.length < 40 ? cursorStillFor + dt : 0

        // Petting: quick back-and-forth right on top of the spider.
        // Only a reversal made on top of it counts, at stroking pace: a
        // pointer whipped across it and back from outside is not a pet.
        let near = cursor.distance(to: pos) < 40 * config.scale
        if !near { lastPetSign = 0 }
        if near && d.length > 1.2 && cursorVel.length < 700 * config.scale {
            let sign: CGFloat = d.x >= 0 ? 1 : -1
            if sign != lastPetSign {
                if lastPetSign != 0 { pettingScore = min(pettingScore + 0.42, 1.6) }
                lastPetSign = sign
            }
        }
        pettingScore = max(0, pettingScore - dt * 0.55)
        // A pointer whipped right over it, over and over, is being chased
        // about — which a playful spider may take as a game, a timid one not.
        if !near { rushed = false } else if !rushed, cursorVel.length > 1400 * config.scale, !isHeld, mode != .clinging,
                  cursorHunt == .none, laser == nil, pettingScore < 0.4 {
            rushed = true
            remember(.chased, 0.2)
        }
        // (Not while it has the pointer marked as prey: that is not a pet.)
        if pettingScore > 0.85, cursorHunt == .none {
            remember(.petted, dt / 6)
            happy.value = max(happy.value, 0.85)
            if emote == .none { setEmote(.hearts, 1.0) }
            if mode == .attached, gestureReady, activity != .wiggle, activity != .dance, activity != .groove, chance(dt * 1.5) {
                beginActivity(chance(0.6) || lastGesture == .dance ? .wiggle : .dance, dur: 0.9)
            }
            wake()
        }
    }

    // MARK: Attached

    private func updateAttached(dt: CGFloat) {
        keepFooting()
        guard var here = map.resolve(anchor, cornerRadius: Spider.cornerRadius * config.scale),
              let loop = map.loop(anchor.loopID) else {
            // A page's ledge gone from under it (clicked through to another
            // page, say): it shoots a line up to catch itself on.
            detachAndFall(lineUp: Spider.isPageLedge(anchor.loopID))
            return
        }
        // Standing on something being carried about: its surfaces are where
        // they were laid out, and it is that much further on (see `riding`).
        here.pos += rideShift
        if inHabitat { underfoot = map.owner(of: anchor) }

        surfaceMotion = surfacePrev.map { here.pos - $0 } ?? .zero
        surfacePrev = here.pos

        // Safety nets. A window that jumps a long way in one poll has gone
        // somewhere we cannot follow (another Space, another display), and a
        // walk that goes nowhere means the surface under it is not what we
        // think it is. Either way, let go rather than pace in mid-air.
        if loop.kind.onWindow {
            if let prev = lastLoopRect, abs(prev.midX - loop.rect.midX) + abs(prev.midY - loop.rect.midY) > 400 {
                lastLoopRect = nil
                detachAndFall()
                return
            }
            lastLoopRect = loop.rect
        } else {
            lastLoopRect = nil
        }
        if speed > 4 {
            if pos.distance(to: stuckPos) < 0.5 {
                stuckFor += dt
                if stuckFor > 1.2 { stuckFor = 0; detachAndFall(); return }
            } else {
                stuckFor = 0
                stuckPos = pos
            }
        } else {
            stuckFor = 0
        }

        // Activity clock. Some activities have a moment in the middle where
        // something happens, so those are checked before the generic reset.
        activityTime += dt
        decisionIn -= dt * config.liveliness * lerp(1, 0.55, drowsy)
        restedFor = (activity == .rest || activity == .sleep) ? restedFor + dt : 0
        progressActivity(dt: dt)
        if musicSteady, !musicNoticed { noticeMusic() }
        updateGroove(dt: dt)
        // On a hunt nothing else is allowed to run long: a walk toward the
        // prey is re-aimed every second or so, and idle habits are dropped.
        if laser != nil, !inCinema, [.walk, .sneak, .rest, .sleep, .watch, .stare, .groom, .look, .glance, .drum, .eat, .groove, .sigh, .doubleTake].contains(activity) {
            if activityTime > 0.4 { queued = nil; finishActivity() }
        }
        // Likewise its catch, spotted close by: whatever it was idling over
        // is dropped for it — it does not finish its grooming first.
        // (A walk too, unless it is the hunt's own.)
        if caught == nil, laser == nil, departing == nil, !inCinema, pendingDemo == nil, t > huntPauseUntil, activityTime > 0.25,
           [.rest, .watch, .stare, .groom, .look, .glance, .drum, .dance, .peer, .fidget, .scratch, .pushup,
            .legStretch, .wiggle, .armsUp, .curious, .wave, .greet, .stretch, .groove, .sigh, .doubleTake].contains(activity)
            || (huntTarget == nil && [.walk, .sneak, .scurry].contains(activity)),
           prey.contains(where: { $0.state == .loose && $0.noticed && !$0.spurned && $0.pos.distance(to: pos) < 300 * config.scale }) {
            queued = nil
            walkThen = nil
            decisionIn = 0
            finishActivity()
        }
        // Gathering itself for a leap — at its catch, or anywhere at all —
        // with its catch below it on the ground: the aim follows the catch
        // until the moment it goes, so it lands on it, not where it was.
        if mode == .attached, activity == .crouch, pendingJump != nil, caught == nil, cursorHunt == .none,
           let q = prey.first(where: { $0.state == .loose && $0.noticed && !$0.spurned && $0.onSurface && !$0.tucked
                                       && (huntPounce ? $0.id == huntTarget : $0.pos.distance(to: pos) < 300 * config.scale) }),
           surfaceNormal.y < -0.5, q.pos.y < pos.y - 10 * config.scale {
            // How long until it gets there: what is left of the gathering,
            // and the drop.
            let g = -gravity.y
            let fall = max(pos.y - q.pos.y, 0)
            let flight = (-90 + (90 * 90 + 2 * g * fall).squareRoot()) / g
            let aim = q.pos + q.vel * (max(activityDur - activityTime, 0) + flight)
            if ballistic(from: pos, to: aim) != nil {
                pendingJump = aim
                pounceMark = aim
                huntPounce = true
                huntTarget = q.id
            }
        }
        if departing != nil, ![.walk, .turn, .crouch, .shoot, .fasten, .idle].contains(activity), activityTime > 0.4 {
            queued = nil
            finishActivity()
        }
        if friendChase != nil || friendFlee != nil, !inCinema, [.walk, .sneak, .rest, .sleep, .watch, .stare, .groom, .look, .glance, .drum, .fidget, .scratch, .peer, .groove, .sigh, .doubleTake].contains(activity) {
            if activityTime > 0.6 { queued = nil; finishActivity() }
        }
        if caught == nil, huntTarget != nil, prey.contains(where: { $0.id == huntTarget && $0.state == .loose }) {
            let hunting: Set<Activity> = [.walk, .sneak, .scurry, .look, .turn, .crouch, .idle, .startle, .shake]
            if !hunting.contains(activity) { queued = nil; finishActivity() }
            else if [.walk, .sneak, .scurry].contains(activity), activityTime > 1.0, !navLive || huntMoved() {
                activityDur = min(activityDur, activityTime)
            }
        }
        // Playing: no settling down to anything else, and a chase is
        // re-aimed as the toy goes.
        if let play = toyPlay, !inCinema {
            let elsewhere: Set<Activity> = [.rest, .sleep, .watch, .groom, .drum, .dance, .roll, .spin, .pushup,
                                             .legStretch, .scratch, .wave, .greet, .glance, .fidget, .stare, .groove, .sigh, .doubleTake]
            if elsewhere.contains(activity), activityTime > 0.3 { queued = nil; finishActivity() }
            else if play.stage == .play, towLine == nil, [.walk, .sneak, .scurry].contains(activity),
                    activityTime > (toy(play.id)?.inPlay == true ? 0.45 : 0.8) { activityDur = min(activityDur, activityTime) }
        }
        // Stalking the pointer: the same, with the creep re-aimed often.
        if cursorHunt == .stalking {
            let stalking: Set<Activity> = [.walk, .sneak, .scurry, .look, .turn, .crouch, .idle, .startle, .shake, .stare]
            if !stalking.contains(activity) { queued = nil; finishActivity() }
            else if [.walk, .sneak].contains(activity), activityTime > 0.9 { activityDur = min(activityDur, activityTime) }
        }
        if activityTime > activityDur {
            let was = activity
            finishActivity()
            // Done, with nothing to go straight on with: a beat before the
            // next whim (the decision clock runs `liveliness` times fast).
            if was != .idle, activity == .idle, atLeisure { decisionIn = max(decisionIn, whimBeat() * config.liveliness) }
        }
        // Put to bed while you are away: whatever roused it, back to sleep.
        if dormant, activity != .sleep { fallAsleep() }
        if activity == .idle && decisionIn <= 0 { think() }

        // Something has slid in front of where it is standing, or it has been
        // pushed off the screen: get out of the way.
        // Only a window's edge can be covered; the screen's rim, the menu
        // bar and the Dock are always its to walk, whatever overlaps them.
        let onWindow = loop.kind.onWindow && activity != .peekaboo && !calmUnderCover
        let covered = onWindow && (map.seg(anchor).map { !$0.isOpen(at: anchor.t) } ?? true)
        let bodyCovered = onWindow && !map.isVisible(pos, depth: loop.depth)
        // Carried off the screen by a window: no alarm. It carries on for a
        // while — the window may well come back — and only then hauls
        // itself back up into view.
        let offScreen = !map.isOnScreen(here.pos, slack: 20)
        if offScreen {
            offScreenFor += dt
            if offScreenFor > 10, ![.shoot, .crouch, .turn].contains(activity), pendingJump == nil { climbBackOnScreen() }
        } else {
            offScreenFor = 0
        }
        if !offScreen && (covered || bodyCovered) {
            occludedFor += dt
            if occludedFor > 0.05, t > escapeUntil { escapeOcclusion() }
        } else {
            occludedFor = 0
        }

        // Posture targets for whatever it is doing.
        let post = posture()
        // Laden — a catch in its jaws, a toy in tow — it goes slower.
        targetSpeed = config.walkSpeed * post.speed * bout * (caught != nil ? 0.75 : 1) * (towLine != nil ? 0.7 : 1)
        // Taken with the pointer: up on its toes, nose tipped toward it.
        // (Not face on: there the feet are free of the ledge and would
        // rise with it.)
        if landDrop {
            // Still coming down out of a landing: it falls on at its own
            // speed until it reaches its legs, and then they have it —
            // taking most of the blow, and giving under the rest.
            lift.value += lift.velocity * dt
            if lift.value <= 0 || t - landedAt > Spider.landHold {
                lift.value = min(lift.value, 0)
                lift.velocity *= Spider.landAbsorb
                landDrop = false
            }
        } else {
            // A crouch is the body let down toward the ledge on its legs —
            // which fold under it, the feet staying where they are — not
            // the whole spider squashed flat.
            lift.step(to: (post.lift - post.crouch * Spider.crouchDrop + 1.6 * interest * SpiderRenderer.profileAmount(yaw: yaw)) * config.scale, dt: dt)
        }
        // The roll's ups and downs are the shape of the ball on the ledge,
        // frame by frame; a spring would smooth the thump out of them.
        // Nor for a hop, which is over too quick for a spring to keep up
        // with: its ups and downs are already the shape of a hop.
        if activity == .roll {
            lift.value = approach(lift.value, post.lift * config.scale, 40, dt); lift.velocity = 0
        } else if activity == .hop, mode == .attached {
            lift.value = approach(lift.value, (post.lift - post.crouch * Spider.crouchDrop) * config.scale, 45, dt)
            lift.velocity = 0
        }
        if activity != .roll, lift.value < -maxSink(tilt: angleDelta(here.tangent.angle, heading)) {
            // However hard it comes down, the belly never goes into the
            // ledge: the legs bottom out.
            lift.value = -maxSink(tilt: angleDelta(here.tangent.angle, heading))
            lift.velocity = max(lift.velocity, 0)
        }
        skid.step(to: 0, dt: dt)
        skid.value = clamp(skid.value, -8 * config.scale, 8 * config.scale)
        // (The body's lean is a turn in the picture: side on it is the nose
        // coming up, but face on it would tip the whole spider over sideways,
        // so there the head does the looking up on its own.)
        pitch.step(to: post.pitch + interestNose.value * 0.3 * SpiderRenderer.profileAmount(yaw: yaw), dt: dt)
        crouch.step(to: post.crouch, dt: dt)
        wag.step(to: post.wag, dt: dt)
        lid.step(to: post.lid, dt: dt)
        legMode = post.legsFree ? .free : .planted
        sleepiness.step(to: activity == .sleep ? 1 : 0, dt: dt)

        // Slow down through corners so the turn reads. It gets going over
        // a few steps and stops short, the way a spider does; the body
        // leans into a start and rocks forward on a stop.
        let turning = abs(angleDelta(heading, headingTarget))
        let turnFactor = remap(turning, 0.25, 1.2, 1.0, 0.45)
        let wantSpeed = targetSpeed * turnFactor
        let prevSpeed = speed
        speed = approach(speed, wantSpeed, wantSpeed > speed ? 5.5 : 11, dt)
        // Rolling, the ground speed is the roll's own: no working up to it.
        if activity == .roll { speed = config.walkSpeed * post.speed }
        inertia = approach(inertia, clamp((speed - prevSpeed) / max(dt, 0.001) * 0.00035, -0.09, 0.09), 14, dt)

        if speed > 0.5, let loop = map.loop(anchor.loopID) { advanceAlong(loop: loop, dt: dt) }
        if crossedHop {
            crossedHop = false
            replanAfterHop()
        }
        // Somewhere to be: the walk ends there.
        if let g = walkGoal, [.walk, .sneak, .scurry].contains(activity), g.anchor.loopID == anchor.loopID,
           let way = loopWay(to: g.anchor), way.dist <= g.within {
            walkGoal = nil
            activityDur = min(activityDur, activityTime)
        }

        // Ran out of shelf: stop at the lip, have a look over it, and either
        // head back or jump somewhere else.
        if reachedEnd {
            reachedEnd = false
            onLedgeEnd()
        }

        // Frame on the surface: +y is the outward normal, +x runs along the
        // edge, and walking the other way is a mirror image.
        surfaceNormal = here.normal
        travelLocal = V2(1, 0)
        let speedFrac = min(speed / max(config.walkSpeed, 1), 1.4)
        headingTarget = here.tangent.angle
        runNose = -0.05 * speedFrac - inertia

        gaitPhase += speed / (strideNow * config.scale) * dt
        if gaitPhase > 1 { gaitPhase -= gaitPhase.rounded(.down) }

        // Body follows the anchor with a little lag, so moving windows drag it.
        if !anchorValid { anchorPos = here.pos; anchorValid = true }
        anchorGlide = approach(anchorGlide, 45, 2.5, dt)
        anchorPos = approach(anchorPos, here.pos, anchorGlide, dt)

        // Walking bob: a small rise and fall twice a cycle, plus a sway along
        // the direction of travel once a cycle. The planted feet stay put, so
        // the legs flex against it. Breathing when still.
        // One gentle rise per step (two steps a cycle), not a buzz.
        let bobAmp = speedFrac * 1.0 * boutBob * worn.bob * config.scale * (activity == .roll ? 0 : 1)
        var bob = sin(gaitPhase * 4 * .pi) * bobAmp * 0.5 + sin(gaitPhase * 2 * .pi) * bobAmp * 0.3
        var sway = cos(gaitPhase * 2 * .pi) * bobAmp * 0.3
        if naturalWalk {
            // Walking the natural way the body rides its legs: it settles a
            // touch as a set of them comes up off the ledge and rises again
            // as they come down to take its weight, and surges a little on
            // each push — in time with the steps it is really taking.
            let up = legs.reduce(0) { $0 + $1.lift } / CGFloat(max(legs.count, 1))
            bob = bobAmp * 1.1 * (Spider.natBobLevel - up)
            sway = sin(gaitPhase * 4 * .pi) * bobAmp * 0.18
        } else if refinedWalk {
            // Walking the refined way, likewise: it settles a little as a
            // set of legs comes up off the ground, rises as they come down
            // and take its weight, and surges a touch with every push.
            let up = legs.reduce(0) { $0 + $1.lift } / CGFloat(max(legs.count, 1))
            bob = bobAmp * 2.6 * (Spider.refBobLevel - up)
            sway = sin(gaitPhase * 4 * .pi) * bobAmp * 0.16
        }
        let breathe = bodyWobble.value(t * (activity == .sleep ? 0.6 : 1.0))
            * (activity == .sleep || activity == .rest ? 1.1 : 0.45) * config.scale
        // Interested, it leans along the ledge toward the pointer: the body
        // shifts and the planted feet stay put.
        let toward = clamp((cursor - pos).dot(here.tangent) / (90 * config.scale), -1, 1)
        interestLean.step(to: toward * interest * 4 * config.scale * SpiderRenderer.profileAmount(yaw: yaw), dt: dt)
        // Dancing, the body goes with the beat straight off the music's
        // clock — no spring in between to put it behind.
        let grooveUp = gf.up * config.scale, grooveAlong = gf.along * config.scale * mirrorSign
        pos = anchorPos + here.normal * (bob + lift.value + breathe + grooveUp)
            + here.tangent * (sway + interestLean.value + skid.value + grooveAlong)
        // Walking the refined way, it tucks into an inside corner, close
        // enough for its legs to reach the walls either side (see `refTuckAt`).
        refRide = bob + lift.value + breathe + grooveUp
        if refinedWalk || refTuck.value != 0 || refTuck.velocity != 0 {
            refTuck.step(to: refinedWalk ? refTuckAt(here.pos) : 0, dt: dt)
            if !refinedWalk, abs(refTuck.value) < 0.01, abs(refTuck.velocity) < 0.01 { refTuck.value = 0; refTuck.velocity = 0 }
            pos -= here.normal * refTuck.value
        }
        // Out in the wind, the body is pushed over its planted feet with
        // every gust (the legs flex against it); a big one, and it flattens
        // itself to the ledge and holds on.
        if weatherOnIt, !sheltered {
            pos += here.tangent * (here.tangent.x * windOn.value * 1.8 * config.scale)
            if abs(windOn.value) > 1.2, here.normal.y > 0.5, t > braceAfter, [.walk, .idle, .look, .glance, .stare].contains(activity) {
                braceAfter = t + randRange(7, 15)
                queued = nil
                walkThen = nil
                beginActivity(.brace, dur: randRange(1.2, 2.2))
            }
        }

        // Every so often it looks over at you — a three-quarter turn of the
        // body, briefly. (Walking, how much it goes turned round to you is
        // its carriage's: see "Body language".)
        glanceIn -= dt
        if glanceIn <= 0 {
            glanceIn = randRange(3, 9) / lerp(0.4, 1.8, personality.affection)
            let when: Set<Activity> = Spider.debugNoBodyLanguage ? [.walk, .idle, .look, .rest] : [.idle, .look, .rest]
            if glance == 0, when.contains(activity) {
                glance = randRange(0.3, 0.55)
                glanceUntil = t + randRange(0.7, 1.6)
            }
        }
        if glance > 0, t > glanceUntil { glance = 0 }

        reactToCursor(dt: dt)
        footing = map.seg(anchor).map { (anchor.loopID, anchor.segIdx, anchor.t, $0.a, $0.b) }
    }

    /// The edge it stood on at the end of the last frame, and where on it.
    private var footing: (loopID: String, segIdx: Int, t: CGFloat, a: V2, b: V2)?

    /// Its place is kept as a distance along the edge from one end. An edge
    /// that moves as a whole (a window dragged) carries it along, as it
    /// should. But one that changes shape instead — a window resized from
    /// the far end, the Dock growing as an app opens — would slide it along
    /// the edge on still legs, as if on ice. So then it keeps its place on
    /// the ground: only the edge's own movement under it, toward or away,
    /// takes it along.
    private func keepFooting() {
        guard let was = footing, was.loopID == anchor.loopID, was.segIdx == anchor.segIdx, was.t == anchor.t,
              let seg = map.seg(anchor) else { return }
        guard (seg.a - was.a).distance(to: seg.b - was.b) > 0.25 else { return }
        let stood = was.a + (was.b - was.a).normalized * was.t
        anchor.t = projectOnSegment(stood, seg.a, seg.b).t
    }

    // MARK: Posture

    /// The balled-up body is not a true ball: an egg, a bit longer along
    /// the ledge than it is tall, in sprite units. A rolling egg does not
    /// keep a level middle — it climbs onto its long side and drops off it
    /// again, twice a turn — and that lumpiness is what makes the roll
    /// look like a body rather than a picture turning.
    static let ballAlong: CGFloat = 20
    static let ballAcross: CGFloat = 17
    static let rollWindup: CGFloat = 0.25
    static let rollFraction: CGFloat = 0.55
    /// How far the push off its back legs lifts it, going into the ball.
    static let rollHop: CGFloat = 9
    /// How far it tips forward into the ball on that push, before it
    /// touches down and the ground takes over the turning.
    static let rollTip: CGFloat = 0.6
    /// The roll in three parts: 0 winding up, 1 rolling, 2 landing out of
    /// it — and how far through that part it is.
    private func rollPhase() -> (phase: Int, v: CGFloat) {
        let u = activityDur > 0 ? clamp(activityTime / activityDur, 0, 1) : 1
        let windup = Spider.rollWindup
        let roll = Spider.rollFraction
        if u < windup { return (0, u / windup) }
        if u < windup + roll { return (1, (u - windup) / roll) }
        return (2, (u - windup - roll) / max(1 - windup - roll, 0.01))
    }
    /// How high the ball's middle sits off the ledge, turned by `spin`
    /// (0 = upright, long side down): the egg's radius toward the ground.
    private static func ballHeight(spin: CGFloat) -> CGFloat {
        let sn = sin(spin), cs = cos(spin)
        return ((ballAlong * sn) * (ballAlong * sn) + (ballAcross * cs) * (ballAcross * cs)).squareRoot()
    }
    /// The lift that puts the ball, turned by `spin`, down on the ledge.
    private static func ballLift(spin: CGFloat) -> CGFloat {
        ballHeight(spin: spin) + SpiderRenderer.ground - SpiderRenderer.ballCentre.y
    }
    /// Ground speed at the start of the roll, in points a second: a linear
    /// run-down from here covers the one turn the roll takes.
    private var rollPeakSpeed: CGFloat {
        let turn = 2 * .pi - Spider.rollTip
        let r = (Spider.ballAlong + Spider.ballAcross) / 2 * config.scale
        // ∫₀¹ (1 - 0.85v) dv = 0.575
        return turn * r / (0.575 * Spider.rollFraction * max(activityDur, 0.3))
    }

    private struct Posture {
        var speed: CGFloat = 0
        var lift: CGFloat = 0
        var pitch: CGFloat = 0
        var crouch: CGFloat = 0
        var wag: CGFloat = 0
        var lid: CGFloat = 0
        var legsFree = false
    }

    private func posture() -> Posture {
        var p = Posture()
        let u = activityDur > 0 ? clamp(activityTime / activityDur, 0, 1) : 1
        switch activity {
        case .idle:
            break
        case .walk:
            p.speed = 1 + speedWobble.value(t) * 0.12
            // Jumping spiders go in bursts: a few steps, a stop to look
            // about, a few more. The pauses come mid-walk, not at the ends.
            if activityTime > walkPauseAt, activityTime < walkPauseAt + walkPauseFor {
                p.speed = 0
                p.pitch = 0.05
                // (Up on its toes to look round at you.)
                p.lift = checkIn != nil ? 1.4 : 0.5
            } else if activityTime >= walkPauseAt + walkPauseFor, activityDur - activityTime > 1.2 {
                walkPauseAt = activityTime + randRange(0.9, 2.2)
                walkPauseFor = randRange(0.25, 0.7)
            }
            switch gaitStyle {
            case .normal: break
            case .bouncy: p.lift = 2
            case .tiptoe: p.lift = 3.5; p.speed *= 0.8
            case .lumber: p.lift = -1.5; p.speed *= 0.7; p.wag = 0.5
            }
            // Off to its seat for the film: a slow crawl, no hurry.
            if inCinema { p.speed *= Spider.cinemaPace }
        case .sneak:
            p.speed = 0.42
            p.crouch = 0.4
            p.pitch = -0.08
        case .scurry:
            p.speed = 1.9
            p.pitch = -0.12
        case .look:
            p.lift = 1.5
            p.pitch = 0.06
        case .rest:
            p.lift = -4
            p.crouch = 0.28
            p.lid = 0.35
        case .groom:
            p.pitch = -0.15
            p.legsFree = true
        case .sleep:
            p.lift = -5
            p.crouch = 0.4
            p.lid = 1
            p.legsFree = true
        case .wave:
            p.lift = 2
            p.pitch = 0.16
            p.legsFree = true
        case .startle:
            p.lift = 5 * (1 - u)
            p.pitch = 0.3 * (1 - u)
        case .crouch:
            // Gather, then the pounce wiggle — the tell of a jumping spider.
            p.crouch = 0.85
            p.pitch = -0.1
            p.wag = u > 0.3 ? 1 : 0
        case .turn:
            // Turning on the spot: the feet step round in waves while the body
            // swings through the front view. A hop turn lifts slightly at the
            // middle; a shuffle turn stays low.
            switch turnStyle {
            case .hop:
                p.lift = sin(u * .pi) * 3
            case .shuffle:
                p.crouch = 0.18 * sin(u * .pi)
            }
        case .peek:
            p.pitch = -0.38
            p.lift = -1
            p.legsFree = false
        case .stretch:
            // Up on tiptoe with everything extended, then back down.
            p.lift = sin(u * .pi) * 6
            p.pitch = sin(u * .pi) * 0.22
            p.legsFree = true
        case .shake:
            p.lift = 1
        case .wiggle:
            p.wag = 1.4
            p.lift = 1.5
        case .bounce:
            // Bobbing on springy legs: down onto them and up on them, three
            // times, every foot staying where it is — it never leaves the
            // ledge, whichever way up that is (a jump is a `.hop`).
            let b = abs(sin(u * .pi * 3))
            let env = min(1, u * 8, (1 - u) * 8)
            p.lift = 3.5 * b * env
            p.crouch = 0.3 * (1 - b) * env
        case .curious:
            p.pitch = -0.2
            p.lift = 2
            p.legsFree = true
        case .fidget:
            p.legsFree = true
        case .scratch:
            p.pitch = 0.08
            p.legsFree = true
        case .armsUp:
            // Rears back a little with both front legs thrown high.
            p.pitch = 0.22 * sin(min(u * 2, 1) * .pi / 2)
            p.lift = 2
            p.legsFree = true
        case .roll:
            // Gathers itself first — feet planted, crouching and rocking
            // back — then tucks into a ball and rolls forward along the
            // ledge, the ball actually turning with the ground it covers,
            // and lands out of it with a squash before the feet come down.
            let r = rollPhase()
            let peak = rollPeakSpeed / max(config.walkSpeed, 1)
            switch r.phase {
            case 0:
                // Sinks and rocks back, drawing its legs in from the back
                // pair forward; then, at the last, a shove off the back
                // legs that pitches it up and forward into the ball.
                let sink = smoothstep(min(r.v / 0.65, 1))
                let push = max(0, (r.v - 0.65) / 0.35)
                p.crouch = 0.6 * sink
                p.pitch = 0.22 * sink
                p.lift = -3 * sink + Spider.rollHop * push * push
                p.speed = peak * push * push
                p.legsFree = r.v > 0.3
            case 1:
                // Comes down out of the hop onto the ledge, and from then on
                // sits on it — the egg riding up and down as it turns —
                // running down as it goes, as anything rolling does.
                let ground = Spider.ballLift(spin: rollSpin)
                let fall = min(r.v / 0.15, 1)
                p.lift = lerp(Spider.rollHop, ground, fall * fall)
                p.speed = peak * (1 - 0.85 * r.v)
                p.legsFree = true
            default:
                // Sits a beat where it stopped while the legs come out,
                // then comes up onto them with a bit of a spring in it.
                let up = easeOutBack(max(0, (r.v - 0.15) / 0.85), 1.4)
                p.lift = lerp(Spider.ballLift(spin: rollSpin), 0, up)
                p.crouch = 0.5 * (1 - r.v)
                p.speed = peak * 0.15 * (1 - min(r.v / 0.35, 1))
                p.legsFree = r.v < 0.7
            }
        case .dance:
            p.lift = 1.5 + abs(sin(u * .pi * 6)) * 3
            p.wag = 1.6
            p.pitch = sin(u * .pi * 6) * 0.08
        case .glance:
            p.lift = 1
        case .peer:
            // Nose right down to the ledge, then a look up at the end.
            p.pitch = u < 0.8 ? -0.42 : -0.42 + (u - 0.8) * 2.5
            p.lift = -3
        case .pushup:
            p.lift = -4 + (1 - abs(sin(u * .pi * 4))) * 5
            p.legsFree = false
        case .legStretch:
            p.pitch = -0.06
            p.lift = 1
            p.legsFree = true
        case .spin:
            p.legsFree = true
        case .shoot:
            // Rears up to aim: one front leg pointing where the line goes.
            p.pitch = 0.18
            p.lift = 1.5
            p.crouch = 0.15
            p.legsFree = true
        case .eat:
            // Head down over the meal, low, front legs holding it.
            p.pitch = -0.16
            p.lift = -2.5
            p.crouch = 0.15
            p.legsFree = true
        case .stare:
            // Sat still, face on, watching you.
            p.lift = -1
            p.crouch = 0.12
        case .hop:
            // A small hop straight up and down, with the weight in it: it
            // sinks onto its legs, springs off them — the body going first,
            // the feet the last of it to leave the ledge — flies, and comes
            // down onto its legs, giving under the landing before it
            // straightens up again.
            // One for joy (see `leapForJoy`) gathers itself lower first.
            let (stage, v) = hopPhase()
            let sink: CGFloat = joyLeapFrom == activityStarted ? 0.65 : 0.4
            switch stage {
            case 0:
                p.crouch = sink * smoothstep(v)
                p.pitch = -0.06 * smoothstep(v)
            case 1:
                p.crouch = sink * (1 - v * v)
                p.lift = Spider.hopTakeoff * v * v
                p.pitch = -0.06 * (1 - v)
            case 2:
                p.lift = Spider.hopTakeoff + 4 * Spider.hopHeight * v * (1 - v)
                p.legsFree = true
            case 3:
                let give = v < 0.4 ? sin(v / 0.4 * .pi / 2) : 1 - smoothstep((v - 0.4) / 0.6)
                p.lift = v < 0.4 ? Spider.hopTakeoff * (1 - give) : 0
                p.crouch = 0.5 * give
            default:
                break
            }
        case .drum:
            // Braced low on the back three pairs, abdomen quivering in time,
            // while the front pair beat on the surface.
            p.crouch = 0.18
            // Dips with each of the slower beats.
            let u = activityTime.truncatingRemainder(dividingBy: 1.45) / 1.45
            let together = u >= 0.5 && u < 0.72 ? max(0, sin(((u - 0.5) / 0.22 * 3).truncatingRemainder(dividingBy: 1) * .pi)) : 0
            p.lift = -1 - together * 1.5
            p.pitch = -0.06
            p.wag = drumBeat() > 0.5 ? 1.2 : 0.4
            p.legsFree = true
        case .greet:
            // Up on its toes, facing you, both front legs raised in greeting.
            // (No lean: face on, a lean would read as a sideways tilt.)
            p.lift = 3
            p.legsFree = true
        case .peekaboo:
            // Creeping to the edge low; popping out tall with the front legs
            // up — "boo!"
            let out = (peek?.stage ?? 0) >= 3
            p.speed = peekPace / max(config.walkSpeed, 1)
            p.crouch = out ? 0 : 0.3
            p.lift = out ? 3 : -2
            p.pitch = out ? 0.2 : -0.1
            p.legsFree = out
        case .fasten:
            // Sticking silk down: backs its abdomen onto the surface with
            // a few dabs, low, tail end pressed in, abdomen working.
            let dab = 0.5 + 0.5 * sin(u * .pi * 3)
            p.crouch = 0.3 + dab * 0.2
            p.lift = -1.5 - dab * 1.5
            p.pitch = 0.16 + dab * 0.1
            p.wag = 0.8 + dab * 0.6
        case .groove:
            // The dance itself is laid over this, beat by beat (see
            // `grooveBody`); the legs are its own (`updateGrooveLegs`).
            p.lift = 0.5
            p.legsFree = true
        case .watch:
            // On the floor: lying down flat, head tipped right up at the
            // picture. On the ceiling: hanging as usual, head turned to it.
            if surfaceNormal.y > 0 {
                p.lift = -5
                p.crouch = 0.34
                p.pitch = 0.12
            } else {
                p.lift = -1
                p.pitch = 0.08
            }
            p.lid = 0.06
        case .brace:
            // Flattened to the surface, legs wide, eyes screwed up: holding
            // on through a gust or a downpour. (It leans into the wind on top
            // of this: see `updateAttached`.)
            p.lift = -3.5
            p.crouch = 0.55
            p.lid = 0.45
        case .bask:
            // Stretched out low in the sun, face tipped up to it, eyes half
            // shut.
            p.lift = -3
            p.crouch = 0.2
            p.pitch = 0.07
            p.lid = 0.55
        case .feel:
            // Leaning in to what it is feeling, the nose tipped to it.
            let up = feelAt.map { clamp(toLocal($0).y / 40, -0.4, 0.5) } ?? 0
            p.pitch = -0.06 + up * 0.35
            p.lift = 1
            p.legsFree = true
        case .drink:
            // Let down low on its legs, head tipped right down to the water
            // — as far down as the water is — and held there, sipping; up
            // again at the end.
            let down = smoothstep(clamp(activityTime / 0.7, 0, 1)) * smoothstep(clamp((activityDur - activityTime) / 0.5, 0, 1))
            let deep = sipAt.map { clamp(-toLocal($0).y / 30, 0.3, 1) } ?? 0.6
            p.pitch = -0.46 * down * (0.6 + 0.4 * deep)
            p.lift = -3.5 * down * deep
            p.crouch = 0.2 * down
            p.legsFree = true
        case .doubleTake:
            // Stopped dead — then up on its toes with the start of it as it
            // snaps round, and settling to stare.
            let s = activityTime
            let jolt = s > 0.15 ? sin(clamp((s - 0.15) / 0.3, 0, 1) * .pi) : 0
            p.lift = 3 * jolt + (s > 0.45 ? 1 : 0)
            p.pitch = 0.08 * jolt
        case .sigh:
            // A big breath in — up a little, nose up — and out: down on its
            // legs, eyes half shut (head and tail droop with it: see "Body
            // language"); then slowly back up.
            let (up, down) = sighBreath(u)
            p.lift = 2.6 * up - 4.2 * down
            p.crouch = 0.3 * down
            p.pitch = 0.1 * up - 0.1 * down
            p.lid = 0.6 * down
        }
        // How it carries itself on the move (see "Body language"): eased
        // out again over whatever it does when it stops.
        if Spider.onFoot.contains(activity) || activity == .idle || activity == .look {
            p.pitch += worn.pitch * SpiderRenderer.profileAmount(yaw: yaw)
            p.lift += worn.lift
            if Spider.onFoot.contains(activity) { p.speed *= worn.pace }
        }
        // Standing, it is never quite still: a slow shift of weight.
        if p.speed == 0 && activity != .sleep && activity != .roll {
            p.lift += liftWobble.value(t) * 0.8
        }
        // How it carries itself: low and flat, or up on its toes.
        if activity != .sleep && activity != .rest && activity != .roll && activity != .crouch {
            p.lift += gait.liftOffset
        }
        // Out in weather: hunched against the wind and the cold, slower
        // going into the wind, and eyes screwed up against sand and snow.
        if weatherOnIt { weatherPosture(&p) }
        return p
    }

    /// Mid-activity events: the flip in a turn, the shake's wobble, and so on.
    private func progressActivity(dt: CGFloat) {
        switch activity {
        case .turn:
            break   // the flip happens in updateYaw, as it passes the front view
        case .shake:
            // A rapid wobble that dies away — throwing off whatever the
            // weather left on it.
            let decay = max(0, 1 - activityTime / activityDur)
            headingVel += sin(activityTime * 62) * 6 * decay
            wag.value = decay * 1.2
            if shookAt != activityStarted {
                shookAt = activityStarted
                shakeOff()
            }
        case .hop:
            // Off the top of the push, a leap for joy goes up for real.
            if joyLeapFrom == activityStarted, mode == .attached, hopPhase().stage >= 2 { leapForJoy() }
        case .crouch:
            if activityTime > activityDur {
                // A pounce at the pointer is aimed where the pointer is now.
                if cursorHunt == .pouncing, pendingJump != nil { aimPounceAtCursor() }
                launchPendingJump()
            }
        case .shoot:
            // The line races out to its mark, then it lets go of the ledge.
            shotProgress = clamp(activityTime / max(activityDur - 0.05, 0.05), 0, 1)
            if activityTime > activityDur {
                if shotPurpose == .climb { climbOutOnLine() } else { launchSwing() }
            }
        case .drum:
            // A note now and then, on the beat.
            if emote == .none, drumBeat() > 0.5, chance(dt * 1.2) { setEmote(.note, 1.0) }
        case .peekaboo:
            progressPeekaboo(dt: dt)
        case .drink:
            // Sipping: now and then a ring spreads from its mouth.
            rippleIn -= dt
            if sipWater, let w = sipAt, rippleIn <= 0, activityTime > 0.6 {
                rippleIn = randRange(0.9, 1.6)
                ripple(at: w + V2(randRange(-1.5, 1.5), 0) * config.scale, size: 1.6)
            }
        case .feel:
            // A front leg on the water: rings spread with each touch.
            rippleIn -= dt
            if let w = waterTouch, rippleIn <= 0 {
                rippleIn = 0.57
                ripple(at: w + V2(randRange(-3, 3), 0) * config.scale, size: 1.8)
            }
        case .groove:
            progressGroove(dt: dt)
        case .eat:
            let u = clamp(activityTime / max(activityDur, 0.1), 0, 1)
            caught?.eaten = easeInOutSine(u) * (caught?.kind.bitter == true ? 0.08 : 0.9)
            if let c = caught, c.state != .caught { caught = nil; activity = .idle }
        case .roll:
            // The ball turns with the ground it rolls over, so it never
            // slides; whatever is left of the turn is finished as it lands.
            let r = rollPhase()
            switch r.phase {
            case 0:
                // Tips forward into the ball on the push off.
                let push = max(0, (r.v - 0.65) / 0.35)
                rollSpin = -Spider.rollTip * push * push
                rollTravel = 0
                rollLanded = false
                rollTouched = false
            case 1:
                // Down out of the hop onto the ledge with a thump.
                if !rollTouched, r.v >= 0.15 {
                    rollTouched = true
                    fatten.velocity = -4
                    stretch.velocity = 2.5
                }
                // Turns with the ground it covers, about whatever radius of
                // the egg is down at the moment: fast over its short side,
                // slower over the long.
                rollTravel += speed * dt
                rollSpin = max(rollSpin - speed * dt / (Spider.ballHeight(spin: rollSpin) * config.scale), -2 * .pi)
                rollSpinEnd = rollSpin
            default:
                rollSpin = lerp(rollSpinEnd, -2 * .pi, smoothstep(r.v))
                if !rollLanded {
                    rollLanded = true
                    crouch.velocity = 5
                    stretch.velocity = 3
                }
            }
        case .spin:
            // Two quick turns back to back.
            if activityTime > 0.02 {
                pendingDir = -walkDir
                turnStyle = .hop
                beginActivity(.turn, dur: 0.55)
                queue(.turn, 0.55)
            }
        case .rest:
            // Nodding off: the longer it rests, the more likely it sleeps.
            if t - lastUserActivity > lerp(60, 10, personality.laziness) * lerp(1, 0.35, drowsy), restedFor > lerp(6, 3, drowsy),
               chance(dt * lerp(0.06, 0.4, personality.laziness) * lerp(1, 2.5, drowsy)) {
                beginActivity(.sleep, dur: randRange(15, 45) * lerp(1, 2, drowsy))
            }
        case .sleep:
            if !fullScreenApp, !dormant, cursor.distance(to: pos) < 90 * config.scale && cursorVel.length > 40 {
                wake()
                beginActivity(.startle, dur: 0.6)
                startled.velocity = 10
                setEmote(.surprise, 0.7)
                remember(.startled, 0.6)
                noteFright(from: cursor)
            }
        default:
            break
        }
    }

    private func finishActivity() {
        if activity == .crouch || activity == .shoot { return }   // handled by progressActivity
        if activity == .eat { finishMeal() }
        if activity == .sleep { wokeUp = true }
        if [.walk, .sneak, .scurry].contains(activity), queued == nil, let (next, dur) = walkThen {
            walkThen = nil
            beginActivity(next, dur: dur)
            return
        }
        // (Turning round to set off: what the walk is for goes on with it.)
        let turningToGo = activity == .turn && queued.map { Spider.onFoot.contains($0.0) } == true && !Spider.debugNoBodyLanguage
        if !turningToGo { walkThen = nil }
        if let (next, dur) = queued {
            queued = nil
            beginActivity(next, dur: dur)
        } else if wokeUp {
            wokeUp = false
            beginActivity(.stretch, dur: 1.5)
            queue(.shake, 0.55)
        } else {
            activity = .idle
            activityTime = 0
        }
    }

    private func beginActivity(_ a: Activity, dur: CGFloat) {
        if a != .peekaboo { peek = nil; peekPace = 0 }
        // The Z's belong to the sleep: when it ends — however it ends —
        // the last of them fade out at once rather than following it about.
        if activity == .sleep, a != .sleep, emote == .zzz {
            emoteDur = 0.8
            emoteTime = 0.6
        }
        activity = a
        activityTime = 0
        activityDur = dur
        turned = false
        activityStarted = t
        if Spider.gestures.contains(a) {
            lastGestureAt = t
            lastGesture = a
            gestureGap = randRange(10, 18) * lerp(1.25, 0.8, personality.playfulness)
        }
        liftsOuterPair = SpiderRenderer.profileAmount(yaw: yaw) < 0.5
        for i in legs.indices { legs[i].poseFrom = legs[i].foot }
        if a == .turn {
            turnFromYaw = yaw == 0 ? 0.01 : yaw
            turnGait = 0
            if pendingDir == walkDir { pendingDir = -walkDir }
        }

        if a == .wave || a == .groom || a == .wiggle { happy.value = max(happy.value, 0.35) }
        if a == .glance, !Spider.debugNoBodyLanguage { glanceDepth = randRange(0.45, 0.8) }
        if a == .sleep { setEmote(.zzz, dur) }
        if a == .wiggle && emote == .none { setEmote(.note, min(dur, 1.0)) }
        if a == .walk {
            // A first pause a little way in, on longer walks; none on a
            // short one, and none when it is going somewhere on purpose.
            let purposeful = huntTarget != nil || laser != nil || homing != nil || build != nil || towLine != nil || mealCarry != nil || inCinema || t < bedBoundUntil || (confined && !inBox) || cursorHunt != .none || coverGoal != nil || walkGoal != nil
            walkPauseAt = (dur > 2.2 && !purposeful && chance(0.7)) ? randRange(0.7, 1.6) : 99
            walkPauseFor = randRange(0.25, 0.7)
        }
        if a == .walk || a == .sneak || a == .scurry {
            bout = randRange(0.72, 1.28)
            boutBob = randRange(0.7, 1.3) * gait.bobMul
            boutStride = randRange(24, 32) * gait.strideMul
            let roll = CGFloat.random(in: 0...1)
            switch gait.style {
            case .mixed:
                gaitStyle = roll < 0.55 ? .normal : (roll < 0.72 ? .bouncy : (roll < 0.87 ? .tiptoe : .lumber))
            case .march: gaitStyle = roll < 0.85 ? .normal : .bouncy
            case .bouncy: gaitStyle = roll < 0.8 ? .bouncy : .normal
            case .tiptoe: gaitStyle = roll < 0.8 ? .tiptoe : .normal
            case .lumber: gaitStyle = roll < 0.8 ? .lumber : .normal
            case .scurry:
                gaitStyle = roll < 0.7 ? .normal : .bouncy
                bout *= 1.35
                boutStride *= 0.85
            }
            if gaitStyle == .bouncy { boutBob *= 1.6 }
            // Out and about, it keeps to one manner of going for the outing.
            if mood == .roam, atLeisure {
                if let m = manner {
                    bout = m.pace * randRange(0.94, 1.06)
                    boutBob = m.bob
                    boutStride = m.stride
                    gaitStyle = m.style
                } else {
                    manner = Manner(sneaks: a == .sneak, pace: bout, bob: boutBob, stride: boutStride, style: gaitStyle)
                }
            }
        }
    }

    private func queue(_ a: Activity, _ dur: CGFloat) {
        queued = (a, dur)
    }

    /// Face the given way along the surface, turning round first if needed.
    /// `then` is what to do once facing that way.
    private func turnTo(_ dir: CGFloat, then next: Activity, for dur: CGFloat) {
        if dir == walkDir {
            beginActivity(next, dur: dur)
            return
        }
        pendingDir = dir
        turnStyle = chance(0.5) ? .hop : .shuffle
        beginActivity(.turn, dur: randRange(0.8, 1.0))
        queue(next, dur)
    }

    /// Hanging under something with a surface not far below: let go of it.
    /// Returns false if there is nothing to drop onto.
    @discardableResult
    private func dropOffUnderside() -> Bool {
        guard surfaceNormal.y < -0.5 else { return false }
        // Whatever is below, even if it is barely below: a low window leaves
        // hardly any gap between hanging under it and standing on the floor.
        guard let spot = map.nearestSpot(to: pos + V2(0, -60), within: 150 * config.scale, excluding: anchor.loopID),
              spot.point.y < pos.y - 4, abs(spot.point.x - pos.x) < 80 else { return false }
        pendingJump = spot.point
        beginActivity(.crouch, dur: randRange(0.3, 0.45))
        return true
    }

    private func onLedgeEnd() {
        if confined, !inBox, !hangOnly {
            // Ran out of edge on the way home: decide again from here.
            activity = .idle
            activityTime = 0
            decisionIn = 0.1
            return
        }
        if confined, inBox, chance(0.85) {
            // At the edge of its patch: turn back rather than leap off it.
            turnTo(-walkDir, then: .walk, for: randRange(1.5, 4.0))
            return
        }
        if inCinema {
            // The end of the floor is where its seat is: stop here and
            // settle, rather than pacing back the other way.
            activity = .idle
            activityTime = 0
            decisionIn = 0.1
            return
        }
        if build != nil {
            // Spinning: the end of the wall is where it hops across.
            activity = .idle
            activityTime = 0
            decisionIn = 0
            return
        }
        if departing != nil {
            // On its way home: on from here some other way.
            departCornered = true
            activity = .idle
            activityTime = 0
            decisionIn = 0
            return
        }
        if friendChase != nil || friendFlee != nil {
            // Mid-game: cornered, it leaps next time.
            if friendFlee != nil { fleeCornered = true }
            activity = .idle
            activityTime = 0
            decisionIn = 0
            return
        }
        if navLive {
            // On its way by the tank's ways, and this is the end of the
            // surface: if the way over it was counting on here is not to be
            // had, that way costs more — then it decides again from here.
            if var trip = navTrip, routeHop != nil, let e = trip.hopEdges.first {
                trip.penalty[e, default: 0] += 400
                trip.bestLeft = .infinity
                trip.bestAt = t
                navTrip = trip
            }
            walkGoal = nil
            routeHop = nil
            activity = .idle
            activityTime = 0
            decisionIn = 0
            return
        }
        if caught == nil, huntTarget != nil {
            // Mid-hunt: no sightseeing, just decide again from here.
            activity = .idle
            activityTime = 0
            decisionIn = 0
            return
        }
        let roll = CGFloat.random(in: 0...1)
        if roll < 0.45, surfaceNormal.y < -0.5, dropOffUnderside() {
            return
        } else if roll < 0.3, let spot = bestJumpSpot(from: pos, exclude: anchor.loopID) {
            startJump(to: spot.point)
        } else if roll < 0.75 {
            // Lean out over the edge for a look before heading back.
            beginActivity(.peek, dur: randRange(0.9, 2.0))
            queue(.turn, randRange(0.8, 1.0))
            pendingDir = -walkDir
            turnStyle = chance(0.5) ? .hop : .shuffle
        } else {
            turnTo(-walkDir, then: .walk, for: randRange(1.5, 4.0))
        }
    }

    private func advanceAlong(loop start: SurfaceLoop, dt: CGFloat) {
        var loop = start
        var remaining = speed * dt
        var guardCount = 0
        while remaining > 0.0001 && guardCount < 8 {
            guardCount += 1
            let seg = loop.segs[anchor.segIdx]
            // Furthest it can go on this edge before something in front of the
            // edge — or the end of it — stops it. Playing peek-a-boo it goes
            // behind the window on purpose.
            let through = activity == .peekaboo
            let lim = through ? (walkDir > 0 ? seg.len : 0) : seg.limit(from: anchor.t, dir: walkDir)
            let room = walkDir > 0 ? lim - anchor.t : anchor.t - lim
            if remaining <= room {
                anchor.t += walkDir * remaining
                remaining = 0
                break
            }
            anchor.t = lim
            remaining -= room
            let atSegEnd = walkDir > 0 ? lim >= seg.len - 0.01 : lim <= 0.01
            if !atSegEnd {
                // Ran into a window in front: this is the end of the ledge.
                reachedEnd = true
                speed = 0
                break
            }
            // At a corner: carry on round it if the next edge is open there.
            let n = loop.segs.count
            let nextIdx = walkDir > 0 ? anchor.segIdx + 1 : anchor.segIdx - 1
            let canContinue = loop.closed || (nextIdx >= 0 && nextIdx < n)
            // Where this surface meets another (in the habitat), it may go
            // on onto that one instead — and at the end of its own, must.
            if map.hasJunctions {
                let own = canContinue ? loop.segs[(nextIdx + n) % n] : nil
                let ownOn = own.map { o in
                    (activity != .roll || o.normal.y > Spider.rollFloor)
                        && (through || o.isOpen(at: (walkDir > 0 ? 0.5 : o.len - 0.5)))
                } ?? false
                if let onto = crossJunction(from: loop, at: walkDir > 0 ? anchor.segIdx + 1 : anchor.segIdx, ownWayOn: ownOn),
                   let other = map.loop(onto.loopID) {
                    anchor = onto
                    loop = other
                    lastLoopRect = nil
                    continue
                }
            }
            guard canContinue else { reachedEnd = true; speed = 0; break }
            let wrapped = (nextIdx + n) % n
            let next = loop.segs[wrapped]
            let entryT: CGFloat = walkDir > 0 ? 0 : next.len
            // A ball does not roll round onto the side or the underside of
            // anything: it comes to a stop on the top.
            if activity == .roll, next.normal.y <= Spider.rollFloor {
                speed = 0
                break
            }
            guard through || next.isOpen(at: entryT + (walkDir > 0 ? 0.5 : -0.5)) else {
                reachedEnd = true
                speed = 0
                break
            }
            anchor.segIdx = wrapped
            anchor.t = entryT
        }
        let seg = loop.segs[anchor.segIdx]
        anchor.t = clamp(anchor.t, 0, seg.len)
    }

    /// How often, walking past where another surface meets its own, it
    /// goes off along that one instead.
    private static let junctionChance: CGFloat = 0.3

    /// Where it goes at vertex `vertex` of the loop it is walking, if not on
    /// along that loop: onto a surface that meets it there (in the habitat:
    /// the end of a vine on a stone, one branch across another, a stem off
    /// the rim of a pot) — the same way round, so its belly stays to what it
    /// is on, as round any corner. At the end of its own surface it must;
    /// where its own goes on, now and then it takes the other instead —
    /// though not on its way somewhere, and never rolling.
    private func crossJunction(from loop: SurfaceLoop, at vertex: Int, ownWayOn: Bool) -> Anchor? {
        guard activity != .roll, activity != .peekaboo, anchor.segIdx < loop.segs.count else { return nil }
        let meets = map.junctions(from: loop.id, at: vertex)
        guard !meets.isEmpty else { return nil }
        let heading = loop.segs[anchor.segIdx].dir * walkDir
        var ways: [(anchor: Anchor, along: V2, j: SurfaceJunction)] = []
        for j in meets {
            guard let l = map.loop(j.to), !l.segs.isEmpty else { continue }
            let n = l.segs.count
            let idx: Int
            if walkDir > 0 {
                guard l.closed || j.toVertex < n else { continue }
                idx = j.toVertex % n
            } else {
                guard l.closed || j.toVertex > 0 else { continue }
                idx = (j.toVertex - 1 + n) % n
            }
            let seg = l.segs[idx]
            let t: CGFloat = walkDir > 0 ? 0 : seg.len
            guard seg.isOpen(at: walkDir > 0 ? min(0.5, seg.len) : max(seg.len - 0.5, 0)) else { continue }
            ways.append((Anchor(loopID: l.id, segIdx: idx, t: t, dir: walkDir), seg.dir * walkDir, j))
        }
        guard !ways.isEmpty else { return nil }
        // On its way somewhere by the surfaces: over here if this is where
        // the way goes over (see `headFor`).
        if let hop = routeHop, hop.from == loop.id {
            let n = max(loop.segs.count, 1)
            if (loop.closed ? hop.fromVertex % n : hop.fromVertex) == (loop.closed ? vertex % n : vertex),
               let way = ways.first(where: { $0.j.to == hop.to && $0.j.toVertex == hop.toVertex }) {
                routeHop = nil
                crossedHop = true
                if errand != nil { errand!.hops.append(routeKey(hop)) }
                return way.anchor
            }
        }
        if ownWayOn {
            let onItsWay = huntTarget != nil || laser != nil || homing != nil || build != nil || towLine != nil || mealCarry != nil
                || departing != nil || cursorHunt != .none || coverGoal != nil || toyPlay != nil || friendChase != nil || friendFlee != nil
                || caught != nil || pendingDemo != nil || walkGoal != nil || routeHop != nil || inquiry != nil || errand != nil
            guard !onItsWay, chance(Spider.junctionChance) else { return nil }
        }
        // Mostly the way that turns it least.
        let weights = ways.map { max(0.05, 1 + $0.along.dot(heading)) }
        var pick = randRange(0, weights.reduce(0, +))
        for (w, way) in zip(weights, ways) {
            if pick < w { return way.anchor }
            pick -= w
        }
        return ways.last?.anchor
    }

    // MARK: Cursor reactions

    private func reactToCursor(dt: CGFloat) {
        guard config.followCursor, !inCinema, cursorHunt == .none, toyPlay == nil else { return }
        let d = cursor.distance(to: pos)
        let busy = [.startle, .crouch, .turn, .sleep, .curious, .stretch, .shake, .roll, .spin, .armsUp, .shoot, .groove].contains(activity)

        // A pointer swept past it, however fast, gets no start out of it: no
        // nervous hop, no "!" — it is only ever curious about the pointer.

        // A pointer hovering close by is interesting.
        let curiousGap = lerp(20, 4, personality.curiosity)
        if !busy && gestureReady && d < 110 * config.scale && d > 36 * config.scale && cursorVel.length < 60
            && t - lastCurious > curiousGap && (activity == .idle || activity == .look || activity == .walk) {
            lastCurious = t
            if chance(lerp(0.2, 0.5, personality.affection)) {
                // Turns to face you and puts both front legs up: hello.
                beginActivity(.greet, dur: randRange(1.8, 2.6))
                happy.velocity = 5
                if chance(0.5) { setEmote(.hearts, 1.0) }
            } else if chance(0.25 + personality.playfulness * 0.2) {
                beginActivity(.armsUp, dur: randRange(0.9, 1.4))
            } else if chance(lerp(0.4, 1.0, personality.curiosity)) {
                beginActivity(.curious, dur: randRange(1.2, 2.2))
                if chance(0.6) { setEmote(.question, 1.2) }
            }
        }
    }

    // MARK: Left to itself
    //
    // With nothing calling on it, what it does next is its own whim — but
    // an animal's whims hang together. For a while it is out and about:
    // off along the way it faces, stopping to look about and going on the
    // same way, over the end of the ledge or round the corner. Then for a
    // while it potters where it is: a groom, a look round, a fidget, a sit.
    // And once it has come round to face one way it keeps to it, rather
    // than turning back the moment it has turned.

    /// How it is spending this stretch of its time, and until when.
    private enum Mood { case roam, potter }
    private var mood: Mood = .roam
    private var moodUntil: CGFloat = 20
    /// When it last came round to face the other way along its edge (or
    /// landed on one), and how long after that it keeps to the way it
    /// faces unless something calls it round.
    private var facedAt: CGFloat = -99
    private var keepHeadingFor: CGFloat = 0
    /// How long the pointer has been at rest, near enough.
    private var cursorStillFor: CGFloat = 0
    /// How it goes about the outing it is on: whether it is creeping, and
    /// its pace and step, which stay much the same bout to bout rather
    /// than changing with every few steps. Picked as the outing's first
    /// bout of walking sets off.
    private struct Manner { var sneaks: Bool; var pace: CGFloat; var bob: CGFloat; var stride: CGFloat; var style: GaitStyle }
    private var manner: Manner?

    /// Facing a new way along its edge: it keeps to it for a while.
    private func faced() {
        facedAt = t
        keepHeadingFor = randRange(6, 14) * lerp(1.2, 0.85, personality.energy)
    }

    /// Free to turn back the way it came on a whim.
    private var mayTurnBack: Bool { t - facedAt > keepHeadingFor }

    /// The stretch it is in is over: out and about or pottering, for a
    /// while. After an outing it mostly settles; after pottering it is
    /// mostly off again. The livelier it is, the longer it is out and the
    /// sooner it is off; the lazier, the longer it sits.
    private func nextMood() {
        let P = personality
        let roamAgain = lerp(0.15, 0.4, P.energy) * lerp(1, 0.5, P.laziness)
        let setOut = lerp(0.6, 0.92, P.energy) * lerp(1, 0.65, P.laziness)
        mood = chance(mood == .roam ? roamAgain : setOut) ? .roam : .potter
        manner = nil
        moodUntil = t + (mood == .roam
            ? randRange(12, 32) * lerp(0.75, 1.35, P.energy)
            : randRange(8, 22) * lerp(1.3, 0.75, P.energy) * lerp(0.9, 1.6, P.laziness) * lerp(1, 1.5, drowsy))
    }

    /// Nothing it is seeing to — no hunt, game, job, errand, trip or film:
    /// only its own whims.
    private var atLeisure: Bool {
        mode == .attached && laser == nil && friendChase == nil && friendFlee == nil && cursorHunt == .none
            && departing == nil && caught == nil && huntTarget == nil && toyPlay == nil && build == nil
            && homing == nil && errand == nil && inquiry == nil && walkGoal == nil && !inCinema
            && coverGoal == nil && riding == nil && webJob == nil && pendingDemo == nil && mealCarry == nil
            && t >= bedBoundUntil && !(confined && !inBox) && interest < 0.5
    }

    /// The pause between one whim and the next, in real seconds: a beat out
    /// and about, longer pottering. An animal finishes one thing, stands a
    /// moment, then does the next; it does not run them all together.
    private func whimBeat() -> CGFloat {
        (mood == .roam ? randRange(0.15, 0.6) : randRange(0.5, 2.0)) * lerp(1.3, 0.7, personality.energy)
    }

    /// How far it could go the way it is heading before it runs out of edge
    /// — a window in front, or the end of a ledge — looking on round a
    /// corner or two; at most `cap`.
    private func roomAhead(cap: CGFloat) -> CGFloat {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return 0 }
        let n = loop.segs.count
        var idx = anchor.segIdx, at = anchor.t, room: CGFloat = 0
        for _ in 0..<3 {
            let seg = loop.segs[idx]
            let lim = seg.limit(from: at, dir: walkDir)
            room += abs(lim - at)
            guard room < cap, (walkDir > 0 ? lim >= seg.len - 0.01 : lim <= 0.01) else { break }
            let next = walkDir > 0 ? idx + 1 : idx - 1
            guard loop.closed || (next >= 0 && next < n) else { break }
            idx = (next + n) % n
            at = walkDir > 0 ? 0 : loop.segs[idx].len
            guard loop.segs[idx].isOpen(at: at + walkDir * 0.5) else { break }
        }
        return min(room, cap)
    }

    /// Which way to wander off: on the way it faces, mostly. It goes back
    /// the way it came when there is hardly any room ahead — and otherwise
    /// only now and then, once it has kept to this way a good while.
    private func wanderWay() -> CGFloat {
        let sc = config.scale
        let room = roomAhead(cap: 300 * sc)
        if room < 45 * sc { return -walkDir }
        if room < 130 * sc, chance(0.5) { return -walkDir }
        if mayTurnBack, chance(lerp(0.12, 0.25, personality.curiosity)) { return -walkDir }
        return walkDir
    }

    // MARK: Body language
    //
    // How it carries itself, and the little things it does with its head,
    // its eyes and its body that say what it is thinking.
    //
    // A walk is not one fixed picture. For a stretch it goes along turned
    // part of the way round to you — a little, half way, or all but face
    // on — with its eyes on you; or side on, with only its head and
    // abdomen come round to watch you; or nose up and strutting, nose down
    // and poking along, tail cocked and bouncing, sashaying, dragging its
    // feet: a while one way, a while another, as its temperament takes it
    // (its carriage). Stopping on its way it may turn to look round at you;
    // walking past, it may do a double take. It cocks its head at you,
    // winks, gives you a slow blink, nods, shakes its head, and sighs.

    /// A way of carrying itself on the move.
    private enum CarriageKind: String { case plain, turned, lookingOn, sassy, shifty, proud, nosy, perky, slouch }

    /// How it carries itself on the move: all nothing for the plain walk.
    private struct Carriage {
        var kind: CarriageKind = .plain
        /// How far round toward you it goes, legs and all: the share of the
        /// way from side on (0) to face on (1).
        var turn: CGFloat = 0
        /// How much further round toward you than that its head and abdomen
        /// are, as a yaw.
        var look: CGFloat = 0
        /// Its lean, nose up (+) or down; its head on its neck, up (+) or
        /// down; its abdomen, tail down (+) or up — all in radians.
        var pitch: CGFloat = 0
        var nod: CGFloat = 0
        var tail: CGFloat = 0
        /// Up on its legs (+) or down on them, in sprite units.
        var lift: CGFloat = 0
        /// Its head cocked over, as `SpiderPose.headCock`.
        var cock: CGFloat = 0
        /// The abdomen swinging from side to side with its steps.
        var sway: CGFloat = 0
        /// How much it bobs, and how quick it goes, as multipliers.
        var bob: CGFloat = 1
        var pace: CGFloat = 1
        /// Its eyes on you as it goes (1), rather than on the way ahead (0);
        /// or, poking along nose down, on the ledge just in front of it (-1).
        var eyes: CGFloat = 0

        /// Turned round to you in any way.
        var towardYou: Bool { turn > 0.001 || look > 0.001 || eyes > 0.001 }

        /// Eased toward `o`, at `rate` a second.
        mutating func ease(to o: Carriage, rate: CGFloat, dt: CGFloat) {
            let k = 1 - exp(-rate * dt)
            turn += (o.turn - turn) * k
            look += (o.look - look) * k
            pitch += (o.pitch - pitch) * k
            nod += (o.nod - nod) * k
            tail += (o.tail - tail) * k
            lift += (o.lift - lift) * k
            cock += (o.cock - cock) * k
            sway += (o.sway - sway) * k
            bob += (o.bob - bob) * k
            pace += (o.pace - pace) * k
            eyes += (o.eyes - eyes) * k
            kind = o.kind
        }
    }
    /// The carriage it means to keep to for now, what it was picked for (a
    /// walk, a sneak, a scurry), and until when.
    private var carriage = Carriage()
    private var carriageFor: Activity = .idle
    private var carriageUntil: CGFloat = -1
    /// The carriage as it has it on right now: eased in as a walk gets
    /// going, out again as it ends, and from one into the next.
    private var worn = Carriage()

    /// Tools only: everything in this section left out, to compare.
    static var debugNoBodyLanguage = ProcessInfo.processInfo.environment["SPIDER_NO_BODY_LANGUAGE"] != nil

    /// How freely it carries itself just now: any way it likes, going about
    /// its own business; side on, in its own manner, about something of its
    /// own (an errand in its tank, home to bed) — no turning to you on the
    /// way; and plain, hunting, chasing, fleeing, carrying a meal, on its
    /// way somewhere it means to get to.
    private enum CarriageScope { case none, sideOn, full }
    private var carriageScope: CarriageScope {
        guard mode == .attached, !Spider.debugNoBodyLanguage else { return .none }
        if atLeisure { return .full }
        // (Getting into place to show a habit off in the Studio, it gets on
        // with it.)
        let urgent = laser != nil || huntTarget != nil || cursorHunt != .none || friendChase != nil || friendFlee != nil
            || departing != nil || coverGoal != nil || toyPlay != nil || caught != nil || riding != nil || t < escapeUntil
            || (confined && !inBox) || inCinema || build != nil || webJob != nil || pendingDemo != nil
        return urgent ? .none : .sideOn
    }

    /// How much of its walking it does turned round toward you, from the
    /// Studio's dial — and the fonder of you, a touch more. Never at the
    /// bottom of the dial, always at the top.
    private var turnedShare: CGFloat {
        let v = habits.walkTurned
        guard v > 0.005 else { return 0 }
        guard v < 0.995 else { return 1 }
        let mid = 0.27 * lerp(0.75, 1.25, personality.affection)
        return v <= 0.5 ? mid * v * 2 : mid + (1 - mid) * pow((v - 0.5) * 2, 1.4)
    }

    /// Walking, sneaking or scurrying: what a carriage is for.
    private static let onFoot: Set<Activity> = [.walk, .sneak, .scurry]

    /// When something last pleased it (a meal, a catch, a game, a stroke)
    /// and when something last shook it (a fling, a fright, being chased
    /// about) — and how much each is still with it, 1 just now, fading to
    /// nothing over a minute or two. Pleased, it struts and bounces along
    /// and its tail goes; shaken, it goes low and careful for a while.
    private var lastGlow: CGFloat = -999
    private var lastShaken: CGFloat = -999
    private var moodGlow: CGFloat {
        let fresh = 1 - clamp((t - lastGlow) / 120, 0, 1)
        return max(fresh, clamp((fed - 0.5) * 1.4, 0, 0.7), clamp(happy.value * 0.8, 0, 0.6))
    }
    private var moodShaken: CGFloat { 1 - clamp((t - lastShaken) / 60, 0, 1) }

    /// A fresh carriage for the walking it is doing (see `Carriage`).
    private func pickCarriage() {
        let P = personality
        let sneaking = activity == .sneak, hurrying = activity == .scurry
        carriageFor = activity
        let glow = moodGlow, shaken = moodShaken
        defer {
            carriageUntil = t + (carriage.kind == .plain ? randRange(2, 4.5) : randRange(3, 7))
            // Pleased with itself, its tail goes as it walks, and it bobs.
            if glow > 0.4, !sneaking, shaken < 0.3 {
                carriage.sway = max(carriage.sway, 0.45 * glow)
                carriage.bob *= 1 + 0.2 * glow
            }
            // Turned to you with someone about, a wink as it goes, now and then.
            if carriage.towardYou, t - lastUserActivity < 60, chance(lerp(0.03, 0.14, P.playfulness) * lerp(0.6, 1.4, P.affection)) {
                pendingWink = t + randRange(0.7, 1.8)
            }
        }
        // (Shaken, it keeps its mind on where it is going.)
        if carriageScope == .full, chance(turnedShare * (1 - 0.6 * shaken)) {
            carriage = turnedCarriage(sneaking: sneaking, hurrying: hurrying)
            return
        }
        // Its frame of mind leans it one way or another: pleased, it struts
        // and bounces; shaken, it goes low and careful, nose down; sleepy
        // or soaked, it drags its feet.
        let damp = max(drowsy, wet * 0.8)
        let kinds: [(CarriageKind, CGFloat)] = [
            (.plain, 2.6 * (1 - 0.4 * glow)),
            (.proud, sneaking ? 0 : lerp(0.15, 1.2, (P.bravery + P.energy) / 2) * (1 + 2 * glow) * (1 - 0.8 * shaken)),
            (.nosy, lerp(0.3, 1.3, P.curiosity) * (hurrying ? 0.5 : 1) * (1 + 2.5 * shaken)),
            (.perky, sneaking ? 0 : lerp(0.15, 1.3, P.playfulness) * (1 + 2 * glow) * (1 - 0.8 * shaken)),
            (.slouch, hurrying ? 0 : (lerp(0.05, 1.1, P.laziness) + drowsy * 1.5) * (1 + 3 * damp) * (1 - 0.7 * glow)),
        ]
        var pick = randRange(0, kinds.reduce(0) { $0 + $1.1 })
        var kind = CarriageKind.plain
        for (k, w) in kinds {
            pick -= w
            if pick <= 0 { kind = k; break }
        }
        carriage = sideOnCarriage(kind)
    }

    /// Walking turned round toward you, eyes on you: how far round, and in
    /// what manner.
    private func turnedCarriage(sneaking: Bool, hurrying: Bool) -> Carriage {
        let P = personality
        var c = Carriage()
        c.eyes = 1
        if sneaking {
            // Creeping along low, with a sideways look at you.
            c.kind = .shifty
            c.turn = randRange(0.18, 0.4)
            c.look = randRange(0.08, 0.18)
            c.lift = -1.2
            c.nod = -0.05
            return c
        }
        let sassy = lerp(0.2, 1.4, P.playfulness)
        let roll = randRange(0, 3 + 1.3 + sassy)
        if roll < 3 {
            c.kind = .turned
            // A little way round, half way, or all but face on.
            let depth = CGFloat.random(in: 0...1)
            c.turn = depth < 0.35 ? randRange(0.2, 0.36) : (depth < 0.75 ? randRange(0.36, 0.55) : randRange(0.55, 0.72))
            // Its head a touch further round than its legs, now and then.
            if chance(0.3) { c.look = randRange(0.04, 0.12) }
            // Chin up as it goes by, the bold ones: showing off to you.
            if chance(lerp(0.1, 0.4, P.bravery)) {
                c.pitch = 0.05
                c.nod = 0.1
                c.lift = 1.5
                c.bob = 1.2
            }
        } else if roll < 3 + 1.3 {
            // Side on, but its head and abdomen come round to watch you go by.
            c.kind = .lookingOn
            c.turn = randRange(0, 0.1)
            c.look = randRange(0.3, 0.48)
            c.nod = randRange(0, 0.08)
        } else {
            // Sashaying: part way round to you, abdomen swinging, tail up.
            c.kind = .sassy
            c.turn = randRange(0.22, 0.42)
            c.sway = randRange(0.7, 1.0)
            c.bob = 1.25
            c.tail = -0.08
            c.pace = 0.92
        }
        if hurrying { c.turn *= 0.6; c.look *= 0.6; c.sway *= 0.5 }
        // Its head cocked at you as often as not — the curious ones more.
        if chance(lerp(0.2, 0.55, P.curiosity)) { c.cock = (chance(0.5) ? 1 : -1) * randRange(0.1, 0.22) }
        return c
    }

    /// Walking side on, in one manner or another.
    private func sideOnCarriage(_ kind: CarriageKind) -> Carriage {
        var c = Carriage()
        c.kind = kind
        switch kind {
        case .proud:
            // Nose up, chest out, up on its legs, a spring in its step.
            c.pitch = randRange(0.07, 0.12)
            c.nod = 0.1
            c.tail = 0.06
            c.lift = randRange(1.5, 2.5)
            c.bob = 1.35
            c.pace = 0.88
        case .nosy:
            // Nose down to the ledge, tail up, eyes on the ground ahead.
            c.pitch = -randRange(0.06, 0.11)
            c.nod = -randRange(0.14, 0.24)
            c.tail = -0.12
            c.lift = -1.5
            c.bob = 0.75
            c.pace = 0.9
            c.eyes = -1
        case .perky:
            // Tail cocked up high, head up, bouncing along.
            c.tail = -randRange(0.24, 0.34)
            c.nod = 0.08
            c.lift = 1
            c.bob = 1.5
            c.pace = 1.05
        case .slouch:
            // Low and droopy: head down, tail dragging, in no hurry.
            c.lift = -2
            c.nod = -0.12
            c.tail = 0.14
            c.pitch = -0.03
            c.bob = 0.6
            c.pace = 0.78
        default:
            break
        }
        return c
    }

    /// Stopped on its way to look round at you: since when, until when, its
    /// head cocked how far.
    private var checkIn: (from: CGFloat, until: CGFloat, cock: CGFloat)?
    /// The stop on its way it last thought about looking round from.
    private var pauseSeen: CGFloat = -1
    /// How likely a stop on its way is to be a look round at you.
    private var checkInOdds: CGFloat {
        min(0.6, 0.12 * lerp(0.5, 1.5, personality.affection) * Habits.weight(habits.glance) * learned.lean(\.glance))
    }

    /// A double take: walking past it had a look at you — then away, and on
    /// a step or two; it is about to stop and snap round to stare. When it
    /// last did, and the look on the way past (in the walk's own time).
    private var lastDoubleTake: CGFloat = -60
    private var takeGlance: ClosedRange<CGFloat>?
    /// When the snap round came, so it is only done once; how it cocks its
    /// head at you after it; and whether it has made up its mind about you.
    private var tookAt: CGFloat = -99
    private var takeCock: CGFloat = 0.24
    private var tookIn = false
    /// Its eyes are wandering about of their own accord (see `updateLook`).
    private var idleEyes = false

    /// A wink, a slow blink: when it began, and one due to begin.
    private var winkFrom: CGFloat = -99
    private var slowBlinkFrom: CGFloat = -99
    private var pendingWink: CGFloat?
    private var pendingSlowBlink: CGFloat?
    /// A nod or a shake of the head, laid over whatever it is doing: when
    /// it began and how long it goes on.
    private var nodFrom: CGFloat = -99
    private var nodFor: CGFloat = 0.9
    private var nodTimes: CGFloat = 2
    private var shakeFrom: CGFloat = -99
    private var shakeFor: CGFloat = 0.9

    /// Its palps (see `SpiderPose.palpNear`): when each was last flicked,
    /// when the next flick is due, and which palp's turn it is.
    private var palpFrom: [CGFloat] = [-9, -9]
    private var palpNext: CGFloat = 1
    private var palpTurn = 0
    /// How far up a palp is through its flick: up quick, down slower.
    private func palpNow(_ k: Int) -> CGFloat {
        let u = (t - palpFrom[k]) / 0.24
        guard u >= 0, u < 1 else { return 0 }
        return u < 0.3 ? smoothstep(u / 0.3) : 1 - smoothstep((u - 0.3) / 0.7)
    }

    /// Its head cocked, on a spring with a little bounce in it.
    private var cock = Spring(0, stiffness: 70, damping: 10)
    /// Cocked at you where it stands: the cock, the next change of it, and
    /// the activity it was for.
    private var standCock: CGFloat = 0
    private var cockIn: CGFloat = 0
    private var cockFor: CGFloat = -1
    /// How far round to you the things it does where it stands turn it,
    /// legs and all (a share of the way to face on), and how much further
    /// its head and abdomen; its head tipped up or down on its neck, and its
    /// abdomen — the looks, the stops, the sigh, the double take. Worked
    /// out each frame by `updateBodyLanguage`.
    private var beatTurn: CGFloat = 0
    private var beatLook: CGFloat = 0
    private var beatNod: CGFloat = 0
    private var beatTail: CGFloat = 0
    /// Its eyes on you where it stands (not darting about), this frame.
    private var eyesOnYou = false
    /// The yaw comes round quickly: the snap of a double take.
    private var yawSnap = false

    private func nod(times: Int = 2) {
        nodFrom = t
        nodTimes = CGFloat(times)
        nodFor = 0.42 * CGFloat(times)
    }
    private func shakeHead(in secs: CGFloat = 0) {
        shakeFrom = t + secs
        shakeFor = randRange(0.8, 1.0)
    }
    private func wink(in secs: CGFloat = 0) { pendingWink = t + secs }
    private func slowBlink(in secs: CGFloat = 0) { pendingSlowBlink = t + secs }

    /// How far a nod has the head down (−), this frame.
    private var nodNow: CGFloat {
        let u = (t - nodFrom) / max(nodFor, 0.01)
        guard u >= 0, u < 1 else { return 0 }
        return -0.3 * (0.5 - 0.5 * cos(u * 2 * .pi * nodTimes))
    }
    /// How far a shake has the head round (as a yaw), and how much it is
    /// shaking at all.
    private var shakeNow: (turn: CGFloat, on: CGFloat) {
        let u = (t - shakeFrom) / max(shakeFor, 0.01)
        guard u >= 0, u < 1 else { return (0, 0) }
        let env = sin(u * .pi)
        return (0.22 * sin(u * 2 * .pi * 2.5) * env, min(1, env * 3))
    }
    /// How far shut a slow blink has its eyes: down, a moment, up again.
    private var slowBlinkNow: CGFloat {
        let u = (t - slowBlinkFrom) / 1.3
        guard u >= 0, u < 1 else { return 0 }
        return u < 0.3 ? smoothstep(u / 0.3) : (u < 0.55 ? 1 : 1 - smoothstep((u - 0.55) / 0.45))
    }
    /// How far shut a wink has one eye of each pair.
    private var winkNow: CGFloat {
        let u = (t - winkFrom) / 0.5
        guard u >= 0, u < 1 else { return 0 }
        return u < 0.25 ? smoothstep(u / 0.25) : (u < 0.55 ? 1 : 1 - smoothstep((u - 0.55) / 0.45))
    }

    /// Every frame, before anything moves: the carriage it is walking with
    /// and the things it does with its head, eyes and body where it stands.
    private func updateBodyLanguage(dt: CGFloat) {
        guard !Spider.debugNoBodyLanguage else { return }
        let onFoot = mode == .attached && Spider.onFoot.contains(activity)
        // The carriage: kept to for a stretch, then another — and a fresh
        // one for a sneak or a scurry. Off its feet, or with something
        // pressing, plain.
        var want = Carriage()
        if onFoot {
            let scope = carriageScope
            if scope != .none {
                if t > carriageUntil || carriageFor != activity { pickCarriage() }
                want = scope == .full || !carriage.towardYou ? carriage : Carriage()
            }
        }
        // (Into a carriage gently; out of one a little quicker, so a look or
        // a groom after a walk is not done half in its walking manner.)
        worn.ease(to: want, rate: onFoot ? 2.2 : 3.5, dt: dt)

        beatTurn = 0
        beatLook = 0
        beatNod = 0
        beatTail = 0
        eyesOnYou = false
        yawSnap = false
        var beatCock: CGFloat = 0
        let attached = mode == .attached

        // Stopped on its way: now and then a look round at you, head
        // cocked, before it goes on.
        if attached, activity == .walk, activityTime > walkPauseAt, activityTime < walkPauseAt + walkPauseFor {
            let id = activityStarted + walkPauseAt
            if pauseSeen != id {
                pauseSeen = id
                if carriageScope == .full, takeGlance == nil, chance(checkInOdds) {
                    let hold = randRange(1.1, 1.8)
                    walkPauseFor = max(walkPauseFor, hold)
                    activityDur = max(activityDur, walkPauseAt + walkPauseFor + 0.8)
                    let cocked = chance(lerp(0.4, 0.8, personality.curiosity))
                    checkIn = (t, t + hold, cocked ? (chance(0.5) ? 1 : -1) * randRange(0.15, 0.3) : 0)
                    let P = personality
                    if chance(lerp(0.04, 0.3, P.playfulness) * lerp(0.6, 1.4, P.affection)) {
                        wink(in: randRange(0.45, 0.7))
                    } else if chance(lerp(0.05, 0.4, P.affection)) {
                        slowBlink(in: randRange(0.35, 0.6))
                    }
                    happy.velocity += 2 * P.affection
                }
            }
        }
        if let c = checkIn {
            if attached, activity == .walk, t < c.until {
                // Round it comes, nearly face on, and back again at the end.
                let u = (t - c.from) / max(c.until - c.from, 0.01)
                let round = smoothstep(clamp(u / 0.25, 0, 1)) * (1 - smoothstep(clamp((u - 0.82) / 0.18, 0, 1)))
                beatTurn = 0.88 * round
                beatCock = c.cock * smoothstep(clamp((u - 0.2) / 0.3, 0, 1))
                eyesOnYou = round > 0.3
            } else {
                checkIn = nil
            }
        }

        // The double take: the look on its way past...
        if attached, activity == .walk, let g = takeGlance, walkThen?.0 == .doubleTake {
            let inIt = smoothstep(clamp((activityTime - g.lowerBound) / 0.15, 0, 1))
                * (1 - smoothstep(clamp((activityTime - g.upperBound) / 0.15, 0, 1)))
            beatTurn = max(beatTurn, 0.45 * inIt)
            eyesOnYou = inIt > 0.5
        } else if activity != .walk && activity != .turn {
            takeGlance = nil
        }
        // ...and, stopped, the snap round to stare.
        if attached, activity == .doubleTake {
            let s = activityTime
            if s >= 0.15 {
                if tookAt != activityStarted {
                    tookAt = activityStarted
                    takeCock = (chance(0.5) ? 1 : -1) * randRange(0.18, 0.28)
                    tookIn = false
                    startled.velocity = max(startled.velocity, 10)
                    stretch.velocity += 2.5
                    setEmote(.exclaim, 0.8)
                }
                beatTurn = 0.92
                yawSnap = s < 0.55
                eyesOnYou = true
                if s > 0.7 { beatCock = takeCock }
                // Having had a good look: pleased to see you, or puzzled.
                if s > 1.15, !tookIn {
                    tookIn = true
                    let P = personality
                    if chance(lerp(0.15, 0.7, P.affection)) {
                        happy.velocity += 5
                        if chance(0.5) { setEmote(.hearts, 1.1) } else { slowBlink() }
                    } else if chance(lerp(0.2, 0.8, P.curiosity)) {
                        setEmote(.question, 1.1)
                    }
                }
            }
        }

        // A shake of the head (see `updateHeadTurn`): it comes part way
        // round to you to do it, so its head has room to go both ways.
        let shake = shakeNow
        if shake.on > 0, attached { beatTurn = max(beatTurn, 0.5 * shake.on) }

        // A sigh: the head and the abdomen droop with the breath out.
        if attached, activity == .sigh {
            let (up, down) = sighBreath(clamp(activityTime / max(activityDur, 0.1), 0, 1))
            beatNod = 0.14 * up - 0.3 * down
            beatTail = -0.06 * up + 0.3 * down
        }

        // Looking about: the head goes with the eyes — up to the sky, down
        // at the ledge — and comes round to look at you when they do.
        var lookingAtYou = eyesOnYou
        if attached, activity == .look, idleEyes {
            let l = toLocalDir(lookSpring.value)
            beatNod += clamp(l.y, -1, 1) * 0.4
            let atYou = 1 - smoothstep(clamp(lookSpring.value.length / 0.3, 0, 1))
            beatLook += 0.3 * atYou
            lookingAtYou = lookingAtYou || atYou > 0.5
        }

        // Its head cocked at you where it stands, looking at you: now one
        // way, now the other, now straight.
        let cockable: Set<Activity> = [.stare, .curious, .glance, .greet, .look]
        if attached, cockable.contains(activity) {
            cockIn -= dt
            if cockFor != activityStarted || cockIn <= 0 {
                let fresh = cockFor != activityStarted
                cockFor = activityStarted
                cockIn = randRange(1.0, 2.6)
                let odds: CGFloat = activity == .stare || activity == .curious ? 0.7 : (activity == .look ? 0.3 : 0.45)
                // (A look about only cocks it looking at you.)
                if activity == .look, !lookingAtYou { standCock = 0 } else {
                    standCock = chance(odds * lerp(0.6, 1.3, personality.curiosity)) ? (chance(0.5) ? 1 : -1) * randRange(0.12, 0.3) : 0
                }
                // Staring at you, the fond ones give you a slow blink.
                // (Not over the top of one it already has coming.)
                if fresh, activity == .stare, pendingSlowBlink == nil, chance(lerp(0.1, 0.6, personality.affection)) { slowBlink(in: randRange(0.9, 2.2)) }
                if fresh, activity == .greet, pendingWink == nil, chance(lerp(0.05, 0.3, personality.playfulness)) { wink(in: randRange(0.8, 1.2)) }
            }
            beatCock += standCock
        } else {
            standCock = 0
        }

        // Its palps: flicked now and then — often with its eye on something
        // (you, the pointer, its prey), now one, now the other, now both;
        // seldom otherwise, and never asleep.
        palpNext -= dt
        if palpNext <= 0 {
            let intent = interest > 0.3 || eyesOnYou || huntTarget != nil || cursorHunt != .none
                || [.stare, .curious, .greet, .glance, .doubleTake, .crouch, .feel].contains(activity)
            let asleep = activity == .sleep || dormant || (mode == .nesting && nestPhase == .sleeping)
            if !asleep, mode == .attached || mode == .dangling {
                if chance(0.25) {
                    palpFrom = [t, t + 0.03]
                } else {
                    palpFrom[palpTurn] = t
                    palpTurn = 1 - palpTurn
                }
            }
            palpNext = intent ? randRange(0.35, 1.3) * lerp(1.3, 0.75, personality.curiosity) : randRange(2.5, 7)
        }

        // Due a wink or a slow blink: now, unless it is asleep or off its feet.
        if let w = pendingWink, t >= w {
            pendingWink = nil
            if attached, activity != .sleep, t - winkFrom > 1.5 { winkFrom = t; happy.velocity += 1.5 }
        }
        if let b = pendingSlowBlink, t >= b {
            pendingSlowBlink = nil
            if attached, activity != .sleep, t - slowBlinkFrom > 2.5 { slowBlinkFrom = t; happy.velocity += 1.5 }
        }

        // (Its head cocked shows face on, and only when it is not busy with
        // the pointer, which has its head already.)
        let cockWant = attached ? (worn.cock + beatCock) * (1 - interest * 0.5) : 0
        cock.step(to: cockWant, dt: dt)
    }

    /// A sigh, `u` of the way through it: how far into the slow breath in
    /// it is, and how far into the quick breath out and the droop after it.
    private func sighBreath(_ u: CGFloat) -> (up: CGFloat, down: CGFloat) {
        let inhaled = smoothstep(clamp(u / 0.35, 0, 1))
        let out = smoothstep(clamp((u - 0.35) / 0.15, 0, 1))
        let back = smoothstep(clamp((u - 0.75) / 0.25, 0, 1))
        return (inhaled * (1 - out), out * (1 - back))
    }

    /// Off along its edge for a step or two, a look at you on the way past
    /// — and on, as if nothing — then it stops dead and snaps round to stare.
    private func startDoubleTake() {
        lastDoubleTake = t
        let walk = randRange(1.5, 2.1)
        turnTo(wanderWay(), then: .walk, for: walk)
        // Plain as you like, going past: nothing to see here.
        carriage = Carriage()
        carriageFor = .walk
        carriageUntil = t + walk + 2
        takeGlance = (walk * 0.3)...(walk * 0.3 + 0.35)
        walkThen = (.doubleTake, randRange(2.0, 2.6))
    }

    /// How long after a double take before another: a gag is no good twice
    /// running.
    private var doubleTakeGap: CGFloat { lerp(260, 110, personality.curiosity) }

    // MARK: - Decisions

    private func think() {
        decisionIn = randRange(1.0, 3.4) / max(config.liveliness, 0.25)
        let idleFor = t - lastUserActivity
        let dCursor = cursor.distance(to: pos)
        let P = personality
        // (A walk to somewhere is over once it is deciding again.)
        walkGoal = nil
        routeHop = nil
        navLive = false

        // Holding on to something being carried about: nothing else till it
        // is put down.
        if riding != nil {
            beginActivity(.brace, dur: 60)
            return
        }

        // Just up after you came back: hello first.
        if greetOnWaking, mode == .attached {
            greetYou()
            return
        }

        // A visitor going home: nothing else now.
        if let dir = departing {
            pursueDeparture(dir)
            return
        }

        // A full-screen video: it watches with you. Mostly it sits, eyes on
        // the screen; now and then a slow amble along the floor, a groom, a
        // glance your way; and only after a very long while does it nod off.
        if inCinema {
            homing = nil
            // A film has started: the spinning is called off, threads and all.
            if build != nil { abandonBuild(); hammock = nil }
            decisionIn = randRange(2.5, 6.0)
            let watching = t - cinemaSince
            // Its seat, picked once: whichever is nearest of the four
            // corners of the screen — a little in from the corner, on the
            // floor or the ceiling — and the door of its hammock, if it has
            // one finished. It crawls there along the rim, up or down, and
            // faces the picture — the middle of the screen — once it is
            // there.
            let f = map.screenFrame(containing: pos)
            if cinemaSeat == nil, let loop = map.loop(anchor.loopID) {
                var seats: [(V2, Bool)] = []
                for s in loop.segs where s.facing == .up || s.facing == .down {
                    seats.append((s.a + s.dir * 24, false))
                    seats.append((s.b - s.dir * 24, false))
                }
                if let h = hammock, h.progress >= 1, f.intersects(h.rect) { seats.append((hammockDoor(h), true)) }
                if let seat = seats.min(by: { $0.0.distance(to: pos) < $1.0.distance(to: pos) }) {
                    cinemaSeat = seat.0
                    cinemaSeatIsNest = seat.1
                }
            }
            if let seat = cinemaSeat, cinemaSeatIsNest, hammock?.progress ?? 0 >= 1 {
                if pos.distance(to: seat) < 40 * config.scale {
                    enterNest()
                } else {
                    walkToward(seat)
                    activityDur = max(activityDur, 3.5)
                }
                return
            }
            if let seat = cinemaSeat, pos.distance(to: seat) > 34 * config.scale {
                walkToward(seat)
                // Never overshoot: the walk ends when it gets there.
                activityDur = min(activityDur, max(pos.distance(to: seat) / max(config.walkSpeed * Spider.cinemaPace * 0.9, 1), 0.4))
                return
            }
            if let seat = cinemaSeat, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count {
                let seg = loop.segs[anchor.segIdx]
                let towardMiddle: CGFloat = (V2(f.midX, f.midY) - seat).dot(seg.dir) >= 0 ? 1 : -1
                if walkDir != towardMiddle {
                    turnTo(towardMiddle, then: .watch, for: randRange(5, 12))
                    return
                }
            }
            let roll = CGFloat.random(in: 0...1)
            if watching > 900, roll < lerp(0.05, 0.3, P.laziness) {
                beginActivity(.sleep, dur: randRange(60, 200))
            } else if roll < 0.74 {
                beginActivity(.watch, dur: randRange(5, 12))
            } else if roll < 0.8 {
                // A stretch without getting up.
                beginActivity(.legStretch, dur: 1.6)
            } else if roll < 0.86 {
                beginActivity(.groom, dur: randRange(1.4, 2.6))
            } else if roll < 0.94 {
                beginActivity(.glance, dur: randRange(0.8, 1.6))
            } else {
                beginActivity(.look, dur: randRange(1.0, 2.0))
            }
            return
        }

        // Spinning its hammock: every idle moment goes on the next step.
        if build != nil {
            pursueBuild()
            return
        }
        // Somewhere to be: heading for the hammock, to build it or to sleep.
        if homing != nil {
            if t - homingSince > 120 { homing = nil } else { pursueHome(); return }
        }

        // A red dot! Nothing else matters.
        if let dot = laser, !inCinema {
            chaseLaser(dot)
            return
        }
        // A game of tag with a friend.
        if let p = friendChase {
            chaseFriend(p)
            return
        }
        if let p = friendFlee {
            fleeFriend(p)
            return
        }
        // On the pointer's trail.
        if cursorHunt == .stalking {
            stalkCursor()
            return
        }

        // Strayed out of its patch: back in first.
        if confined, !inBox {
            returnToBox()
            return
        }
        outOfBoxSince = -1
        returnTheLongWay = false

        // Holding a meal it has not got round to: eat it — somewhere
        // quieter first, if that is where it was taking it.
        if let c = caught, c.state == .caught {
            if let carry = mealCarry, t - carry.since < 10, mode == .attached, pos.distance(to: carry.to) > 26 * config.scale {
                walkToward(carry.to)
                walkThen = (.eat, c.kind.mealTime * randRange(0.9, 1.15))
                return
            }
            mealCarry = nil
            beginActivity(.eat, dur: c.kind.mealTime * randRange(0.9, 1.15))
            return
        }
        // Something to eat about: everything else can wait.
        if caught == nil, !inCinema, let q = quarry() {
            decisionIn = randRange(0.25, 0.7) / max(config.liveliness, 0.25) / (1 + learned.prowess * 2)
            endToyPlay(bored: false)
            // (Lying in wait for just this, or poking about for it: that went well.)
            if let e = errand { endErrand(how: [.ambush, .forage].contains(e.kind) && e.stage == .act ? 1 : 0) }
            hunt(q)
            return
        }
        // A toy it is playing with, or one it feels like playing with.
        if toyPlay != nil || pickToy() {
            playWithToy()
            return
        }
        // A web under way.
        if webJob != nil {
            pursueWeb()
            if webJob != nil || activity != .idle { return }
        }
        // Music just started: it dances — a good long while of it.
        if wantsToGroove {
            startGroove()
            return
        }
        // Somewhere it is off to in its tank, or something it is doing
        // there: on with it.
        if errand != nil, pursueErrand() { return }
        // The weather: shaking itself off, running for cover and sitting it
        // out, bracing, basking, looking up at the sky.
        if weatherOnIt || wet > 0.3 || snowOn > 0.3 || dust > 0.3 || coverGoal != nil, weatherMind() {
            return
        }
        // Just had a fright in its tank: off to somewhere shut in, to get
        // over it.
        if placesOn, let f = lastFright, t - f.at < 10, startHiding(from: f.from) { return }
        // Something new in the tank: looking into it, or starting to.
        if inHabitat, tank != nil, inquiry != nil || startInquiry(), pursueInquiry() {
            return
        }

        // Left alone, it settles down and eventually nods off. The lazy ones
        // do not wait to be left alone — and if it has a hammock, that is
        // where it goes.
        if idleFor > lerp(120, 20, P.laziness) * lerp(1, 0.35, drowsy) * (1 + 2 * hunger) || habits.sleep >= 0.995,
           chance(min(1, lerp(0.1, 0.6, P.laziness) * lerp(1, 1.8, drowsy) * hw(\.sleep))) {
            // In its tank: to where it sleeps best.
            if placesOn, goFor(.sleep) { return }
            if let h = hammock, h.progress >= 1, chance(0.7) {
                goHome(.sleep)
                return
            }
            // The top of a window makes a good bed: if it is not on one,
            // it sets off for the nearest, and sleeps once it gets there.
            if !onWindowTop, t > bedBoundUntil, chance(0.6), nearestWindowTop() != nil {
                bedBoundUntil = t + 45
                think(.moon, for: 2.5)
                goToBed()
                return
            }
            beginActivity(.rest, dur: randRange(8, 20) * (0.7 + P.laziness))
            return
        }
        // On the way to bed, or just arrived: keep going, or settle down.
        if t < bedBoundUntil {
            if onWindowTop {
                bedBoundUntil = -1
                beginActivity(.rest, dur: randRange(4, 8))
                queue(.sleep, randRange(40, 120) * (0.7 + P.laziness))
            } else {
                goToBed()
            }
            return
        }

        // On its way over to see the pointer: on with it, or give it up.
        if pointerTrip != nil, pursuePointerTrip() { return }

        let eyeOnPointer = (config.followCursor || config.approachCursor) && dCursor < 340 && cursorFree(cursor)
            && chance(min(1, lerp(0.1, 0.65, P.curiosity) * hw(\.approach)))
        if eyeOnPointer {
            // Investigate the pointer — from where it stands, if it is
            // already close enough to have its attention. It goes over to
            // a pointer that has come to rest, not after every flick of it
            // across the screen; and not round behind it when it has only
            // just turned this way, unless the pointer has sat there a
            // while — or it would be turning this way and that all day.
            // Only where going will get it there, though (see `pointerWay`),
            // and not to one left lying there untouched a good while.
            if config.approachCursor, dCursor > 70, interest < 0.5, cursorStillFor > 0.4, !pointerSnubbed,
               t - lastUserActivity < Spider.pointerFresh, let way = pointerWay() {
                let along = distanceAlong(to: cursor)
                if abs(along) > 30 * config.scale, along * walkDir > 0 || mayTurnBack || cursorStillFor > 1.5 {
                    pointerTrip = PointerTrip(since: t, best: dCursor, gainAt: t)
                    walkToward(cursor)
                    return
                }
                // Right over it, up on the window it is down in front of: down
                // a line to see it.
                if way == .drop, abs(along) <= 30 * config.scale {
                    dropToPointer()
                    return
                }
            }
            // Otherwise a look at it — though out and about, it mostly
            // keeps an eye on it as it goes.
            if config.followCursor, mood == .potter || interest >= 0.5 || chance(0.4) {
                beginActivity(.look, dur: randRange(0.8, 2.0))
                return
            }
        }

        // Someone is about and there is a window edge to hide behind nearby:
        // peek-a-boo, now and then (or as soon as it can if it was asked to).
        let asked = t < wantsPeekabooUntil
        if asked || (config.followCursor && !eyeOnPointer && dCursor < 520 && t - lastUserActivity < 20
                     && chance(min(1, lerp(0.03, 0.14, P.playfulness) * hw(\.peekaboo)))) {
            if startPeekaboo(reach: asked ? 600 : 260) { wantsPeekabooUntil = -1; return }
            if asked { goHideSomewhere() ; return }
        }

        // In its tank: what it feels like doing there, if anything — a
        // drink, a look out, a rest in its spot, somewhere it hasn't been…
        if placesOn, t >= errandRestUntil, interest < 0.5, startTankGoal() { return }

        // Everything else is a weighted draw. Each weight is the plain
        // frequency scaled by whichever trait it expresses, so a shy spider
        // still dances now and then and a show-off still rests. In a box it
        // takes things easy: slower decisions, more resting, less dashing
        // about, and it never leaves the box.
        let chill: CGFloat = confined ? 0.4 : 1
        if confined { decisionIn *= 2.2 }
        // Run down (Low Power Mode): less play, more lying about.
        let play = lerp(0.25, 2.2, P.playfulness) * chill * lerp(1, 0.5, drowsy)
        let love = lerp(0.2, 2.2, P.affection)
        let lazy = lerp(0.3, 2.4, P.laziness) / chill * lerp(1, 2, drowsy)
        let busy = lerp(0.5, 1.6, P.energy) * chill * lerp(1, 0.55, drowsy)
        var options: [(CGFloat, () -> Void)] = []
        if interest > 0.5 {
            // The pointer has its attention: it stays on it — watching,
            // craning, a greeting or the arms up now and then — and none of
            // the drumming, dancing and wandering off it gets up to alone.
            decisionIn = randRange(1.6, 3.2)
            options.append((10 * hw(\.look), { self.beginActivity(.look, dur: randRange(1.4, 3.0)) }))
            options.append((6 * lerp(0.6, 1.4, P.curiosity) * hw(\.stare), { self.beginActivity(.stare, dur: randRange(2.5, 5)) }))
            options.append((5 * lerp(0.5, 1.5, P.curiosity) * hw(\.curious) * gestureWeight(.curious), { self.beginActivity(.curious, dur: randRange(1.2, 2.2)) }))
            options.append((4 * love * hw(\.greet) * gestureWeight(.greet), { self.beginActivity(.greet, dur: randRange(1.6, 2.4)); self.happy.velocity = 4 }))
            options.append((3 * play * hw(\.armsUp) * gestureWeight(.armsUp), { self.beginActivity(.armsUp, dur: randRange(0.9, 1.4)) }))
            options.append((2 * love * hw(\.wave) * gestureWeight(.wave), { self.beginActivity(.wave, dur: 1.5); self.happy.velocity = 4 }))
            options.append((3 * hw(\.fidget), { self.beginActivity(.fidget, dur: randRange(0.7, 1.2)) }))
            options.append((2 * hw(\.peer), { self.beginActivity(.peer, dur: randRange(1.0, 1.6)) }))
            draw(options)
            return
        }
        // Out and about, or pottering where it is (see "Left to itself"):
        // the same things to choose from, weighted for the mood it is in.
        // (Hanging under something is no place to settle, whatever its
        // mood: it moves on.)
        if t >= moodUntil { nextMood() }
        let roaming = mood == .roam || surfaceNormal.y < -0.5
        let goW: CGFloat = roaming ? 2.4 : 0.15     // off along its edge
        let sitW: CGFloat = roaming ? 0.5 : 1.3     // things done where it stands
        let showW: CGFloat = roaming ? 0.85 : 1.7   // play, and showing off
        let awayW: CGFloat = roaming ? 1.3 : 0.3    // off this surface altogether
        // Settled, it takes its time over things.
        let linger: CGFloat = roaming ? 1 : randRange(1.4, 2.2)
        options.append((30 * busy * hw(\.wander) * goW, {
            let dir = self.wanderWay()
            // (Out and about, a sneaking mood lasts the outing: see `manner`.)
            let sneaks = roaming ? self.manner?.sneaks ?? chance(lerp(0.3, 0.05, P.bravery)) : chance(lerp(0.3, 0.05, P.bravery))
            let hurried = lerp(0.04, 0.22, P.energy) * lerp(1, 0.2, self.drowsy)
            let style: Activity = sneaks ? .sneak : (chance(hurried) ? .scurry : .walk)
            var dur = style == .scurry ? randRange(0.5, 1.2) : randRange(1.4, 5.0)
            // Pottering, it only shifts along a little.
            if !roaming { dur = min(dur, randRange(0.7, 1.6)) }
            self.turnTo(dir, then: style, for: dur)
            // It went somewhere for a reason: having got there, it has a
            // look about, checks on you, or has a peer over the edge.
            if self.queued == nil || self.queued?.0 == style {
                let after = CGFloat.random(in: 0...1)
                let follow: (Activity, CGFloat)? = after < 0.3 ? (.look, randRange(0.7, 1.6))
                    : after < 0.45 ? (.glance, randRange(0.8, 1.4))
                    : after < 0.55 ? (.peer, randRange(1.2, 1.8))
                    : after < 0.62 ? (.groom, randRange(1.4, 2.4)) : nil
                if let f = follow { self.walkThen = f } else { self.walkThen = nil }
            }
        }))
        options.append((10 * hw(\.look) * sitW, { self.beginActivity(.look, dur: randRange(0.7, 2.2) * linger) }))
        options.append((6 * lazy * hw(\.rest) * sitW, {
            // In its tank, a rest is mostly in its spot for resting.
            if self.placesOn, self.t >= self.errandRestUntil - 4, chance(0.65), self.goFor(.rest) { return }
            self.beginActivity(.rest, dur: randRange(3, 8) * linger)
        }))
        options.append((6 * hw(\.groom) * sitW, { self.beginActivity(.groom, dur: randRange(1.4, 2.8) * linger) }))
        options.append((6 * (0.5 + busy * 0.5) * hw(\.fidget) * sitW, { self.beginActivity(.fidget, dur: randRange(0.7, 1.2)) }))
        options.append((4 * hw(\.scratch) * sitW, { self.beginActivity(.scratch, dur: randRange(1.0, 1.6) * linger) }))
        options.append((2 * love * hw(\.wave) * gestureWeight(.wave) * showW, {
            self.beginActivity(.wave, dur: 1.5)
            self.happy.velocity = 4
        }))
        options.append((2 * play * hw(\.wiggle) * gestureWeight(.wiggle) * showW, { self.beginActivity(.wiggle, dur: 0.8) }))
        options.append((3 * love * hw(\.glance) * sitW, { self.beginActivity(.glance, dur: randRange(0.8, 1.6)) }))
        if config.followCursor, dCursor < 520, t - lastUserActivity < 30 {
            options.append((3 * love * hw(\.greet) * gestureWeight(.greet) * showW, {
                self.beginActivity(.greet, dur: randRange(1.8, 2.6))
                if chance(0.5) { self.setEmote(.hearts, 1.0) }
            }))
        }
        // Sitting still, turned to face you, just watching.
        if config.followCursor, dCursor < 560, t - lastUserActivity < 40 {
            options.append((3 * love * lerp(0.6, 1.4, P.curiosity) * hw(\.stare) * sitW, {
                self.beginActivity(.stare, dur: randRange(3, 7) * min(linger, 1.5))
            }))
        }
        // A thought, now and then.
        options.append((4 * lerp(0.5, 1.5, P.curiosity) * (raining ? 1.8 : 1) * hw(\.muse) * sitW, { self.museIfSoMoved(); if self.emote == .none { self.beginActivity(.look, dur: randRange(0.6, 1.2)) } }))
        // Out and about: past you with a look — and a second look (see
        // `startDoubleTake`). Rarely, or it would not be funny.
        if roaming, carriageScope == .full, surfaceNormal.y > -0.5, t - lastDoubleTake > doubleTakeGap {
            options.append((1.4 * lerp(0.5, 1.5, P.curiosity) * lerp(0.6, 1.4, P.playfulness) * hw(\.glance), { self.startDoubleTake() }))
        }
        // Settled where it is: a sigh.
        if !Spider.debugNoBodyLanguage {
            options.append((1.2 * lerp(0.4, 1.8, P.laziness) * lerp(1, 1.6, drowsy) * hw(\.rest) * sitW, {
                self.beginActivity(.sigh, dur: randRange(1.8, 2.4))
            }))
        }

        // Drumming on whatever it is standing on, the way a jumping spider
        // signals: a few bursts of quick taps with its front legs.
        options.append((2.5 * play * lerp(0.6, 1.4, P.energy) * hw(\.drum) * showW, {
            self.beginActivity(.drum, dur: randRange(2.9, 5.8))
            self.setEmote(.note, 1.4)
        }))
        options.append((3 * lerp(0.4, 1.8, P.curiosity) * hw(\.peer) * sitW, { self.beginActivity(.peer, dur: randRange(1.2, 2.0) * min(linger, 1.5)) }))
        options.append((2.5 * lerp(0.5, 1.5, (P.affection + P.bravery) / 2) * hw(\.armsUp) * gestureWeight(.armsUp) * showW, {
            self.beginActivity(.armsUp, dur: randRange(0.9, 1.5))
            if chance(0.5) { self.setEmote(.sparkle, 0.9) }
        }))
        // Only ever on top of something (see `canRoll`) — and not back the
        // way it has only just turned from.
        if let dir = rollWay(), dir == walkDir || mayTurnBack {
            options.append((2 * play * hw(\.roll) * showW, {
                if dir == self.walkDir {
                    self.beginActivity(.roll, dur: randRange(1.5, 1.9))
                    self.queue(.shake, 0.45)
                } else {
                    self.turnTo(dir, then: .roll, for: randRange(1.5, 1.9))
                }
            }))
        }
        options.append((1.5 * play * hw(\.dance) * gestureWeight(.dance) * showW, {
            self.beginActivity(.dance, dur: randRange(1.2, 2.0))
            self.setEmote(.note, 1.4)
        }))
        // Music still on: another dance to it, now and then.
        if mayGrooveAgain {
            options.append((3 * play * hw(\.danceMusic) * showW, { self.startGroove() }))
        }
        // The tank rearranged round it: out exploring, to see what is new.
        if exploring, inHabitat, tank != nil {
            options.append((24 * busy * lerp(0.7, 1.4, P.curiosity) * (roaming ? 1.3 : 0.6), { self.explore() }))
        }
        options.append((1.5 * busy * hw(\.pushup) * showW, { self.beginActivity(.pushup, dur: randRange(1.2, 1.8)) }))
        options.append((1.5 * (0.5 + lazy * 0.5) * hw(\.stretch) * sitW, { self.beginActivity(.legStretch, dur: 1.6) }))
        options.append((1 * play * hw(\.spin) * showW, { self.beginActivity(.spin, dur: 0.1) }))
        // A look back the way it came — once it has kept to this way a while.
        if mayTurnBack {
            options.append((2 * hw(\.look) * sitW, { self.turnTo(-self.walkDir, then: .look, for: randRange(0.6, 1.4)) }))
        }
        if surfaceNormal.y < -0.5 {
            // Hanging under something is no place to linger: let go and
            // drop onto whatever is below — or, with nothing there to drop
            // onto, on along under it.
            options.append((14 * goW, { if !self.dropOffUnderside() { self.turnTo(self.wanderWay(), then: .walk, for: randRange(1.2, 3.0)) } }))
        }
        options.append((8 * hw(\.leap) * chill * awayW, {
            // Mostly somewhere ahead of it: round behind it only once it has
            // kept to this way a while.
            if let spot = self.bestJumpSpot(from: self.pos, exclude: self.anchor.loopID, behind: self.mayTurnBack ? 0.7 : 0.1) {
                self.startJump(to: spot.point)
            } else {
                self.turnTo(self.wanderWay(), then: .walk, for: roaming ? randRange(1.2, 3.0) : randRange(0.7, 1.6))
            }
        }))
        // Paying out a line from the underside of something, down to
        // whatever is below.
        if config.webs, canRappel() {
            options.append((8 * hw(\.rappel) * chill * awayW, { self.dropOnWeb() }))
        }
        // Swinging off on a line, if there is something up ahead to hang it
        // from — not in a box, where there is no room for it.
        if !confined {
            options.append((7 * hw(\.swing) * lerp(0.6, 1.4, P.playfulness) * awayW, {
                if self.config.webs, self.startSwing() { return }
                self.beginActivity(.look, dur: randRange(0.6, 1.2))
            }))
        }
        // A little web in a corner, or under the ledge it is hanging from.
        if leavesTraces, config.webs, !confined, webJob == nil, let site = webSite() {
            options.append((3.5 * lerp(0.6, 1.4, P.laziness) * lerp(0.7, 1.3, P.curiosity), {
                self.webJob = site
                self.pursueWeb()
            }))
        }
        // Spinning a retreat, once, when it has been about for a while.
        if config.hammocks, hammock == nil, t > 45, !confined {
            options.append((1.6 * hw(\.hammock) * lerp(0.6, 1.6, P.laziness), {
                self.goHome(.build)
            }))
        }
        if let h = hammock, h.progress >= 1, !confined {
            options.append((1.5 * lerp(0.2, 2.5, P.laziness) * hw(\.nap), { self.goHome(.sleep) }))
        }
        // A hammock torn by the pointer: back to mend it, before long.
        if let h = hammock, h.progress >= 1, h.damage > 0.08, config.hammocks, !confined {
            options.append((10 * hw(\.hammock), { self.goHome(.mend) }))
        }
        // A hammock left half-spun: back to finish it, before long.
        if let h = hammock, h.progress < 1, config.hammocks, !confined {
            options.append((12 * hw(\.hammock), { self.goHome(.build) }))
        }
        draw(options)
    }

    /// The multiplier one of its habit dials puts on a weight.
    /// (And whatever lean its memories give it: see `TraitShift.lean`.)
    private func hw(_ habit: KeyPath<Habits, CGFloat>) -> CGFloat { Habits.weight(habits[keyPath: habit]) * learned.lean(habit) }

    /// One weighted draw from what it could do. Things dialled down to
    /// never are not in the hat at all; with nothing left in it, it just
    /// stands there until the next thought.
    private func draw(_ options: [(CGFloat, () -> Void)]) {
        let live = options.filter { $0.0 > 0 }
        guard !live.isEmpty else { return }
        let total = live.reduce(0) { $0 + $1.0 }
        var pick = randRange(0, total)
        for (w, act) in live {
            pick -= w
            if pick <= 0 { act(); return }
        }
        live.last?.1()
    }

    /// On its own it only pays out silk from something it is hanging under; if
    /// you ask for it, anywhere with room to descend will do.
    private func canRappel(userAsked: Bool = false) -> Bool {
        guard !inCinema else { return false }
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return false }
        guard pos.y - map.screenFrame(containing: pos).minY > 150 else { return false }
        if userAsked { return true }
        return loop.segs[anchor.segIdx].facing == .down
    }

    /// How it would get to the pointer to see it close to: along its edge,
    /// if that brings it near enough; down a line, if it is up on top of a
    /// window and the pointer is down over the window's face, under it;
    /// otherwise not at all — off along the top of a window it would only
    /// end up pacing about right over a pointer it can never get any nearer.
    private enum PointerWay { case walk, drop }
    private func pointerWay() -> PointerWay? {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return nil }
        let seg = loop.segs[anchor.segIdx]
        let sc = config.scale
        // (How far the pointer is off its edge, + out from the surface.)
        let off = (cursor - pos).dot(seg.normal)
        if abs(off) < Spider.interestRange * sc * 0.75 { return .walk }
        guard off < 0, seg.facing == .up, config.webs, !inCinema, !inHabitat, !confined,
              canRappel(userAsked: true) else { return nil }
        // Over this edge, with room to stand above it…
        let along = (cursor - seg.a).dot(seg.dir)
        guard along > 24 * sc, along < seg.len - 24 * sc else { return nil }
        // …and the way down to it out in the open, in front of everything.
        let x = seg.point(at: along).x
        var y = pos.y - 20 * sc
        while y > cursor.y + 30 * sc {
            guard map.isVisible(V2(x, y), depth: loop.depth) else { return nil }
            y -= 20
        }
        return .drop
    }

    /// On its way over to see the pointer: when it set off, the nearest it
    /// has got, and when it last got any nearer.
    private struct PointerTrip { var since: CGFloat; var best: CGFloat; var gainAt: CGFloat }
    private var pointerTrip: PointerTrip?
    /// It gave up on getting to the pointer: until then — or until the
    /// pointer goes somewhere else — it only watches it.
    private var pointerSnubUntil: CGFloat = -1
    private var pointerSnubAt = V2.zero
    private var pointerSnubbed: Bool {
        t < pointerSnubUntil && cursor.distance(to: pointerSnubAt) < 150 * config.scale
    }

    /// One decision of the way over to the pointer. False when it is over:
    /// it got there, or it is getting no nearer and has lost interest.
    private func pursuePointerTrip() -> Bool {
        guard var trip = pointerTrip else { return false }
        let sc = config.scale
        let d = cursor.distance(to: pos)
        if d < trip.best - 10 * sc { trip.best = d; trip.gainAt = t }
        pointerTrip = trip
        // Near enough for a good look at it: there.
        if d < Spider.interestRange * sc * 0.8 || interest > 0.5 || !config.approachCursor || mode != .attached
            || t - lastUserActivity > Spider.pointerFresh {
            pointerTrip = nil
            return false
        }
        // Getting no nearer, or the pointer is somewhere it cannot get to
        // now: it loses interest, and leaves it be for a while.
        let way = pointerWay()
        guard way != nil, t - trip.gainAt < 3.5, t - trip.since < 15 else {
            pointerTrip = nil
            pointerSnubUntil = t + randRange(25, 50)
            pointerSnubAt = cursor
            return false
        }
        let along = distanceAlong(to: cursor)
        if abs(along) <= 30 * sc {
            pointerTrip = nil
            if way == .drop { dropToPointer(); return true }
            return false
        }
        walkToward(cursor)
        return true
    }

    /// Down a line off the top of the window to the pointer below — and
    /// having had its look, it does not keep going back down to it while
    /// it stays put.
    private func dropToPointer() {
        pointerTrip = nil
        lineOrder = nil
        dropOnWeb()
        pointerDrop = mode == .airborne && rappelAfterCatch
        pointerSnubUntil = t + randRange(45, 90)
        pointerSnubAt = cursor
    }
    /// A pointer that has not moved for this long, seconds, is not worth
    /// going over to.
    private static let pointerFresh: CGFloat = 20

    /// Its line has caught it on the way down to see the pointer: on down
    /// to just over it, a good look, and back up.
    private func planPointerVisit() {
        let screen = map.screenFrame(containing: webAnchor)
        let maxLen = max(40, webAnchor.y - (screen.minY + 30 * config.scale))
        let want = clamp(webAnchor.y - cursor.y - 48 * config.scale, 40 * config.scale, maxLen)
        webPlan = [.descend(want), .linger(randRange(6, 12)), .climbHome]
        lingerUntil = -1
    }

    /// How far along its edge `p` is from it, + the way the edge runs.
    private func distanceAlong(to p: V2) -> CGFloat {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return 0 }
        return (p - pos).dot(loop.segs[anchor.segIdx].dir)
    }

    private func walkToward(_ p: V2) {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        let seg = loop.segs[anchor.segIdx]
        let along = (p - pos).dot(seg.dir)
        let dir: CGFloat = along >= 0 ? 1 : -1
        turnTo(dir, then: .walk, for: clamp(abs(along) / max(config.walkSpeed, 1), 0.5, 4.5))
    }

    /// A window has come over it: get out from under, at once. The edge it
    /// is on is behind that window now — nothing to walk on, not even to
    /// the open part of it further along — so it leaves it: a line
    /// straight up to climb to whatever is above, or it lets go and drops,
    /// often shooting a line on the way down to swing out on. Failing all
    /// of those, it leaps for the nearest clear spot.
    private func escapeOcclusion() {
        abandonBuild()
        occludedFor = 0
        escapeUntil = t + 2.0
        queued = nil
        pendingJump = nil
        wake()
        startled.velocity = 6
        setEmote(.surprise, 0.5)
        let screen = map.screenFrame(containing: pos)
        let roomBelow = pos.y - screen.minY > 70
        let ceiling = config.webs && !inCinema ? map.ceiling(above: pos, maxRise: 900) : nil
        // Clear if nothing sits over the line's path just under that edge.
        let ceilingClear = ceiling.map { map.isVisible($0 - V2(0, 4), depth: Int.max) } ?? false
        if ceilingClear, let c = ceiling, !roomBelow || chance(0.6) {
            // Up and out: a line to the ceiling, then hand over hand to the top.
            shotTarget = c
            shotPurpose = .climb
            shotProgress = 0
            beginActivity(.shoot, dur: 0.2)
        } else if roomBelow {
            detachAndFall(lineUp: chance(0.5))
        } else if let spot = bestJumpSpot(from: pos, exclude: anchor.loopID) {
            startJump(to: spot.point)
        } else if let spot = map.nearestSpot(to: pos, within: 900) {
            startJump(to: spot.point)
        } else {
            detachAndFall()
        }
    }

    /// Off the screen, and still off it after a good while: a line straight
    /// up to the nearest thing on screen above it — the top of the screen
    /// if nothing else — and a haul back up it. Off the side, the line goes
    /// up to the screen's edge and it swings in under it. Without silk, it
    /// leaps for the nearest spot on screen instead.
    private func climbBackOnScreen() {
        offScreenFor = 0
        abandonBuild()
        queued = nil
        pendingJump = nil
        walkThen = nil
        wake()
        let screen = map.screenFrame(containing: pos)
        let x = clamp(pos.x, screen.minX + 24, screen.maxX - 24)
        if config.webs {
            let top = V2(x, (map.menuBarBottom(for: screen) ?? screen.maxY) - 4)
            var target = map.ceiling(above: V2(x, pos.y), maxRise: 4000) ?? top
            if !map.isOnScreen(target, slack: -4) || target.y <= pos.y + 30 { target = top }
            if target.y > pos.y + 30 {
                shotTarget = target
                shotPurpose = .climb
                shotProgress = 0
                beginActivity(.shoot, dur: 0.25)
                return
            }
        }
        if let spot = map.nearestSpot(to: V2(x, clamp(pos.y, screen.minY + 24, screen.maxY - 24)), within: 1200, excluding: anchor.loopID) {
            startJump(to: spot.point)
        } else {
            detachAndFall()
        }
    }

    /// The line fired straight up has caught: haul up it to the surface.
    private func climbOutOnLine() {
        applyPendingMap()
        attachWeb(at: shotTarget)
        // Up into the habitat, which sits in front of every window: none
        // of them can cover this line.
        if tankClimb { webFromDepth = Int.min }
        webStyle = .hang
        swingPumping = false
        webLenTarget = 26
        hangHeadUp = true
        hurrying = true
        webGrace = 0.3
        decisionIn = 99
        anchorValid = false
        activity = .idle
        queued = nil
    }

    private func wake() {
        if activity == .sleep || activity == .rest {
            beginActivity(.idle, dur: 0.2)
            sleepiness.velocity = -3
            wokeUp = activity == .sleep
        }
        if emote == .zzz { emote = .none }
        lastUserActivity = t
    }

    // MARK: Jumping

    private func startJump(to point: V2) {
        pendingJump = point
        // Face the target first, then gather.
        let d = point - pos
        if let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count {
            let dir: CGFloat = d.dot(loop.segs[anchor.segIdx].dir) >= 0 ? 1 : -1
            if dir != walkDir {
                pendingDir = dir
                turnStyle = .shuffle
                beginActivity(.turn, dur: 0.8)
                queue(.crouch, randRange(0.45, 0.7))
                return
            }
        }
        beginActivity(.crouch, dur: randRange(0.45, 0.7))
    }

    /// In the tank: whether a leap launched at `launch` from `a`, meant to
    /// come down at `b`, would pass right through something solid on the
    /// way (see `SurfaceMap.arcBlocked`).
    private func leapBlocked(from a: V2, launch: V2, to b: V2) -> Bool {
        guard inHabitat, !map.loops.isEmpty else { return false }
        return map.arcBlocked(from: a, launch: launch, to: b)
    }

    private func launchPendingJump() {
        guard let point = pendingJump, var launch = ballistic(from: pos, to: point) else {
            pendingJump = nil
            pendingMap = nil
            glassLeap = false
            departLeap = false
            activity = .idle
            crouch.velocity = -6
            // A pounce at a pointer that has got out of range: nothing doing.
            if cursorHunt == .pouncing { endCursorHunt(nextIn: randRange(5, 10)); setEmote(.question, 1.0) }
            calledOffPounce()
            return
        }
        // Hanging under something and aiming below: it lets go and drops,
        // with a push away from the surface, rather than leaping into it —
        // unless the surface is glass it means to go through.
        if !glassLeap { launch = Spider.pushOff(launch, from: pos, to: point, normal: surfaceNormal) }
        // In the tank, it doesn't leap through walls: an arc that would go
        // right through something solid (a wall, a shut door, a log) on the
        // way, it doesn't try.
        if !glassLeap, !departLeap, leapBlocked(from: pos, launch: launch, to: point) {
            pendingJump = nil
            pendingMap = nil
            activity = .idle
            crouch.velocity = -6
            if cursorHunt == .pouncing { endCursorHunt(nextIn: randRange(5, 10)); setEmote(.question, 1.0) }
            calledOffPounce()
            return
        }
        glassLeap = false
        pendingJump = nil
        launchLoop = anchor.loopID
        launches += 1
        let trailFrom = mode == .attached ? ledgePin() : nil
        mode = .airborne
        air = .jump
        airTime = 0
        // Out past the edge of the screen for good: it catches hold of
        // nothing on the way.
        noAttachFor = departLeap ? 30 : 0.1
        flyingHome = departLeap
        departLeap = false
        vel = launch
        applyPendingMap()
        if let spot = map.nearestSpot(to: point, within: 40 * config.scale) {
            landing = (spot.point, spot.seg.angle, spot.seg.dir)
        }
        maybeTrailLine(from: trailFrom, to: point)
        crouch.velocity = -9
        stretch.velocity = 5
        wag.reset(0)
        legMode = .free
    }

    /// Launch velocity that actually lands on `p1`, or nil if it is out of
    /// range (see `arc`) — or, in the tank, only through something solid.
    private func ballistic(from p0: V2, to p1: V2) -> V2? {
        guard let v = Spider.arc(from: p0, to: p1) else { return nil }
        // (In the tank, no leap through walls: a mark it could only reach
        // through something solid is out of reach.)
        if leapBlocked(from: p0, launch: v, to: p1) { return nil }
        return v
    }

    /// Launch velocity that lands on `p1` (the air's drag aside), or nil if
    /// it is out of range. Picks the flattest arc the spider has the legs
    /// for, just above the minimum-energy solution — so a jump either looks
    /// like a jump or is never attempted.
    static func arc(from p0: V2, to p1: V2) -> V2? {
        let d = p1 - p0
        let g = -gravityPull.y
        let r = d.length
        guard r > 1 else { return nil }
        let vMin = (g * (d.y + r)).squareRoot()
        guard vMin.isFinite, vMin <= maxJumpSpeed else { return nil }
        let v = min(vMin * 1.06, maxJumpSpeed)
        if abs(d.x) < 1 { return V2(0, v) }
        let dx = abs(d.x)
        let v2 = v * v
        let disc = max(0, v2 * v2 - g * (g * dx * dx + 2 * d.y * v2))
        let theta = atan((v2 - disc.squareRoot()) / (g * dx))
        return V2(cos(theta) * (d.x >= 0 ? 1 : -1), sin(theta)) * v
    }

    /// The push it really goes with, meaning to leap at `launch` from `p`
    /// for `point` off a surface facing `normal`: aimed into what it stands
    /// on, it lets go and drops instead (hanging under something, with the
    /// mark below), or pushes off along it.
    static func pushOff(_ launch: V2, from p: V2, to point: V2, normal: V2) -> V2 {
        guard launch.length < 1 || launch.normalized.dot(normal) < -0.05 else { return launch }
        if normal.y < -0.9, point.y < p.y - 4 {
            // Under something flat with the mark below: let go with the
            // push down, and drift out just enough over the fall to come
            // down on it — not short of it, or it drops straight past
            // the ledge it was meant for.
            let g = -gravityPull.y
            let push: CGFloat = 90
            let fall = p.y - point.y
            let time = (-push + (push * push + 2 * g * fall).squareRoot()) / g
            let drift = (point.x - p.x) / max(time, 0.05) * (1 + 0.11 * time)   // (the air's drag)
            return V2(clamp(drift, -700, 700), -push)
        }
        let along = launch - normal * launch.dot(normal)
        return along.clampedLength(220) + normal * 90
    }

    /// `behind` weighs the spots it would have to turn round to face.
    private func bestJumpSpot(from p: V2, exclude: String, behind: CGFloat = 1) -> (anchor: Anchor, point: V2)? {
        let spots = map.sampleSpots(spacing: 40)
        guard !spots.isEmpty else { return nil }
        var scored: [(CGFloat, Anchor, V2)] = []
        let playful = config.approachCursor && cursor.distance(to: p) < 700
        let normal = surfaceNormal
        let ahead = behind == 1 ? nil : map.loop(anchor.loopID).flatMap { l in anchor.segIdx < l.segs.count ? l.segs[anchor.segIdx].dir * walkDir : nil }
        for s in spots {
            let d = s.point.distance(to: p)
            // A short hop straight down onto something below counts too —
            // that is how it gets off the underside of a low window.
            let below = s.point.y < p.y - 20 && abs(s.point.x - p.x) < 60
            guard d > (below ? 28 : 70), d < 680 else { continue }
            var score = s.loop.kind.appeal * appeal(s.point, on: s.loop.kind)
            score *= remap(d, 70, 680, 1.25, 0.45)
            if let box = confine, !box.contains(s.point.point) { score *= 0.03 }
            if s.loop.id == exclude { score *= 0.18 }
            if s.loop.id == anchor.loopID { score *= 0.3 }
            if let a = ahead, (s.point - p).dot(a) < 0 { score *= behind }
            if playful {
                let dc = s.point.distance(to: cursor)
                score *= remap(dc, 0, 500, 1.9, 0.9)
            }
            guard let launch = ballistic(from: p, to: s.point) else { continue }
            // Cannot jump through the thing it is standing on.
            guard launch.normalized.dot(normal) > -0.15 else { continue }
            score *= randRange(0.55, 1.45)
            scored.append((score, s.anchor, s.point))
        }
        guard !scored.isEmpty else { return nil }
        scored.sort { $0.0 > $1.0 }
        let pick = scored[Int.random(in: 0..<min(4, scored.count))]
        return (pick.1, pick.2)
    }

    // MARK: Airborne

    private func updateAirborne(dt: CGFloat) {
        airTime += dt
        noAttachFor = max(0, noAttachFor - dt)
        vel += gravity * dt
        // Blown off course a little by the wind.
        if weatherOnIt { vel.x += windPush * 0.36 * dt }
        vel *= exp(-0.22 * dt)
        pos += vel * dt

        // Pouncing on the pointer: passing within reach of it, it takes hold.
        if cursorHunt == .pouncing {
            let prev = pos - vel * dt
            if projectOnSegment(cursor, prev, pos).dist < 30 * config.scale {
                catchCursor()
                return
            }
        }

        // Fly head-first: mirror to face the direction of travel, pitch into
        // the arc, but never roll past 50 degrees or it reads as tumbling.
        var flightHeading: CGFloat?
        if vel.length > 60 {
            // (Dropping on a line, or shooting one, it keeps the side it
            // shows you: turned face on there, its head would be beside its
            // abdomen.)
            if airShot == nil, draglineCatchY == nil { facing = vel.x >= 0 ? 1 : -1 }
            let pitchAngle = angleDelta(0, vel.angle + (vel.x < 0 ? .pi : 0))
            flightHeading = clamp(pitchAngle, -0.85, 0.85)
            if air == .thrown { flightHeading! += sin(t * 9) * 0.18 }
        }
        let mayGrabSoon = noAttachFor <= 0 && !(huntPounce && pounceMark.map { pos.distance(to: $0) > 60 * config.scale && (($0 - pos).dot(vel) > 0 || vel.y > 0) } == true)
        // Coming in to land: over the last stretch it turns to meet the
        // surface — feet first, even upside down under a window — and the
        // legs reach out for it, so touchdown is the end of a movement
        // rather than a snap. A leap knows where it is going; a fall or a
        // throw looks ahead for whatever it is about to hit.
        landingReach = 0
        var aim = landing
        if huntPounce, let mark = pounceMark, pos.distance(to: mark) > 60 * config.scale { aim = nil; landing = nil }
        // On a line, or shooting one, it is not looking for a landing.
        let onLine = airShot != nil || draglineCatchY != nil
        // The faster it is going, the further ahead it looks, and the
        // sooner it turns: it has to be feet first by the time it hits.
        if aim == nil, !onLine, mayGrabSoon, vel.length > 40,
           let spot = map.nearestSpot(to: pos + vel * 0.12, within: max(70 * config.scale, vel.length * 0.1),
                                      excluding: airTime < 0.28 ? launchLoop : nil) {
            aim = (spot.point, spot.seg.angle, spot.seg.dir)
        }
        if let a = aim {
            let to = a.point - pos
            let closing = to.dot(vel) > 0 || vel.length < 80
            let range = max((landing != nil ? 130 : 70) * config.scale, vel.length * 0.22)
            if closing { landingReach = clamp(1 - to.length / range, 0, 1) }
        }
        if landingReach > 0.001, let a = aim {
            let w = smoothstep(landingReach)
            let along = (vel.length > 30 ? vel : a.point - pos).dot(a.dir)
            if w > 0.45 { facing = along >= 0 ? 1 : -1 }
            let fh = flightHeading ?? heading
            headingTarget = fh + angleDelta(fh, a.angle) * w
        } else if let mark = airShot?.target ?? (draglineCatchY != nil ? webAnchor : nil) {
            // Spinnerets to the mark: it twists to put its abdomen at
            // whatever the line goes to, and hangs in line with it as it
            // falls — the way it will hang once the line takes its weight.
            headingTarget = (pos - mark).angle + (facing < 0 ? .pi : 0)
        } else if let fh = flightHeading {
            headingTarget = fh
        }
        // Tumbling after a hard bounce: round and round, slowing — until a
        // landing is close, when it rights itself to meet it feet first.
        if abs(tumbleVel) > 0.5 {
            if landingReach > 0.25 {
                tumbleVel *= exp(-9 * dt)
            } else {
                // Leading the heading's spring so it turns at about this rate.
                headingTarget = heading + tumbleVel * 0.11
            }
            tumbleVel *= exp(-1.1 * dt)
        } else {
            tumbleVel = 0
        }
        legMode = .free
        crouch.step(to: 0, dt: dt)
        lift.step(to: 0, dt: dt)
        pitch.step(to: 0, dt: dt)
        wag.step(to: 0, dt: dt)
        lid.step(to: 0, dt: dt)

        // A pounce: the fangs get whatever they pass — and once it has the
        // catch, it lands on the first thing it comes to.
        if huntPounce {
            snapAtPrey(reach: 6)
            if caught != nil { pounceMark = nil }
        }

        if !flyingHome { bounceOffScreens() }

        // A pounce is aimed at the prey, not at the furniture on the way: it
        // grabs nothing until it is near its mark, or has sailed past it and
        // is on the way down.
        var mayGrab = noAttachFor <= 0
        if huntPounce, let mark = pounceMark {
            let near = pos.distance(to: mark) < 34 * config.scale
            let past = (mark - pos).dot(vel) < 0 && vel.y < 0
            let tooLong = airTime > 1.6
            mayGrab = mayGrab && (near || past || tooLong)
        }
        if mayGrab {
            // The reach grows with speed: at a full fall it covers more
            // than one frame's travel, so it can never step straight over
            // a ledge between one frame and the next.
            let reach = max(18 * config.scale, vel.length * dt * 0.8)
            if let spot = map.nearestSpot(to: pos, within: reach,
                                          excluding: airTime < 0.28 ? launchLoop : nil) {
                // Only grab on if we are moving toward the surface, or slow enough.
                let toward = (spot.point - pos).normalized.dot(vel.normalized)
                // Dropping past the underside of something is not landing
                // on it: an underside is reached from below, or slowly —
                // or by a leap that was aimed there.
                let fromAbove = spot.seg.facing == .down && vel.y < -80 && landing == nil
                if !fromAbove, vel.length < 260 || toward > -0.25 {
                    if bounce(off: spot.seg.normal, at: spot.point) { return }
                    land(on: spot.anchor, seg: spot.seg)
                    return
                }
            }
        }

        // Shooting a line up: a beat to twist round, then the line races
        // out to the mark; when it gets there it is fastened, and the fall
        // goes on on a dragline from here.
        if var shot = airShot {
            let age = t - shot.began
            shot.progress = clamp((age - Spider.airShotAim) / Spider.airShotFlight, 0, 1)
            if shot.progress >= 1 {
                webAnchor = shot.target
                webFromDepth = shot.depth
                webActive = true
                webLen = max(20, pos.distance(to: webAnchor))
                webLenTarget = webLen
                prevHangLen = webLen
                draglineCatchY = shot.catchY
                airShot = nil
                stretch.velocity = 2
            } else {
                airShot = shot
            }
        }
        // On its dragline: the line pays out behind it as it drops, and it
        // takes hold where it decided to before it let go.
        if let catchY = draglineCatchY {
            webLen = max(webLen, pos.distance(to: webAnchor))
            webLenTarget = webLen
            // Its legs are on the line already, paying it out as it drops
            // (see `updateLineLegs`), head down, however it is turned yet.
            hangDelta = clamp(webLen - prevHangLen, 0, 40 * config.scale)
            prevHangLen = webLen
            upness = 0
            climbLayout = 0
            lineGrip = 0
            // Where it meant to, or sooner if it is about to hit the side
            // of the screen: it takes the line up before it smacks in.
            let screen = map.screenFrame(containing: pos)
            let ahead = pos.x + vel.x * 0.12
            let wallSoon = ahead < screen.minX + 40 * config.scale || ahead > screen.maxX - 40 * config.scale
            if (pos.y <= catchY && vel.y < 0) || (wallSoon && webLen > 60) {
                catchDragline()
                return
            }
        } else if airShot == nil, config.webs, !flyingHome, air != .jump || airTime > 1.5 {
            // Nothing planned and nothing under it at all — off the bottom
            // of the world, or a leap that has plainly failed: a line to the
            // ceiling is the last resort, never a habit.
            let aboutToLeave = pos.y < map.worldBounds.minY + 60 && vel.y < 0
            let failedLeap = air == .jump && airTime > 1.5 && vel.y < 0
            if aboutToLeave || failedLeap, map.landingBelow(pos, halfWidth: 24 * config.scale) == nil,
               let c = map.ceiling(above: pos, maxRise: 720) {
                attachWeb(at: c)
                return
            }
        }

        // Off the world entirely: put it back at the top of the main screen
        // — or, in the habitat, which is its whole world, back in the tank.
        if inHabitat, !map.worldBounds.insetBy(dx: -60, dy: -60).contains(pos.point) {
            let f = map.worldBounds
            pos = V2(clamp(pos.x, f.minX + 40, f.maxX - 40), clamp(pos.y, f.minY + 40, f.maxY - 40))
            vel = V2(0, -50)
        } else if !flyingHome, !map.worldBounds.insetBy(dx: -400, dy: -400).contains(pos.point) {
            let f = NSScreen.main?.frame ?? map.worldBounds
            pos = V2(f.midX + randRange(-200, 200), f.maxY - 60)
            vel = V2(0, -50)
        }
    }

    /// The screen's own rim, as a backstop: anything that gets this far
    /// past the edge (a frame's travel at full speed can) meets it the way
    /// it meets any surface — a bounce if it came in hard enough, a landing
    /// on the nearest spot if not.
    private func bounceOffScreens() {
        let f = map.screenFrame(containing: pos)
        let pad = 14 * config.scale
        var hit: (normal: V2, at: V2)?
        if pos.x < f.minX + pad, vel.x < 0 { hit = (V2(1, 0), V2(f.minX + pad, pos.y)) }
        if pos.x > f.maxX - pad, vel.x > 0 { hit = (V2(-1, 0), V2(f.maxX - pad, pos.y)) }
        if pos.y > f.maxY - pad, vel.y > 0 { hit = (V2(0, -1), V2(pos.x, f.maxY - pad)) }
        if pos.y < f.minY + pad, vel.y < 0 { hit = (V2(0, 1), V2(pos.x, f.minY + pad)) }
        guard let h = hit else { return }
        if bounce(off: h.normal, at: h.at, force: true) { return }
        if let spot = map.nearestSpot(to: pos, within: 90) {
            land(on: spot.anchor, seg: spot.seg)
        } else {
            // Nowhere to stand here: stopped at the rim, it drops.
            if h.normal.dot(vel) < 0 { vel -= h.normal * h.normal.dot(vel) }
            pos = h.at
        }
    }

    /// Hitting something in the air — any surface, the same way: going into
    /// it hard enough (how hard is the bounciness dial) and it bounces off,
    /// keeping more of its speed the bouncier it is and sliding on along
    /// the surface a little, and goes tumbling end over end — spun by how
    /// glancing the hit was; gentler than that, and it lands. A leap or a
    /// pounce lands where it was aimed, however it arrives. `force`: the
    /// screen's rim, which it may not pass, so a bounce it gets regardless.
    private func bounce(off normal: V2, at point: V2, force: Bool = false) -> Bool {
        guard !Spider.debugNoBounce, air != .jump, !huntPounce, cursorHunt != .pouncing else { return false }
        let b = clamp(gait.bounciness, 0, 1)
        let into = -vel.dot(normal)                   // speed into the surface
        guard into > 0 else { return false }
        let threshold = b < 0.02 ? CGFloat.greatestFiniteMagnitude : lerp(1250, 400, b) * max(config.scale, 0.5)
        guard into > threshold || (force && into > 60 && b >= 0.02 && into > threshold * 0.5) else { return false }
        let restitution = lerp(0.28, 0.72, b)
        let along = V2(normal.y, -normal.x)          // the surface's direction
        let slide = vel.dot(along) * lerp(0.78, 0.92, b)
        vel = along * slide + normal * (into * restitution)
        pos = point + normal * (2 * config.scale)
        // Spun by the surface catching it as it slides, plus a kick from
        // the knock itself; the harder the hit, the faster the tumble.
        let knock = clamp(into / 900, 0, 1)
        tumbleVel = clamp(-slide / (24 * config.scale) + (chance(0.5) ? 1 : -1) * knock * randRange(6, 12), -20, 20)
        debugBounces += 1
        air = .thrown
        noAttachFor = 0.1
        stretch.velocity = 5 + knock * 6
        if knock > 0.45 { setEmote(.surprise, 0.5); startled.velocity = 6 }
        return true
    }

    private func land(on a: Anchor, seg: Seg) {
        tumbleVel = 0
        // Up a line to the top: it climbs onto what the line hangs from,
        // its front feet already on it, rather than landing there.
        let climbedUp = mode == .dangling && hangHeadUp
        // Off any line it was on: the next starts afresh, hanging head down.
        rappelAfterCatch = false
        pointerDrop = false
        lineOrder = nil
        mantle = nil
        hangHeadUp = false
        flipSign = 0
        climbLayout = 0
        lineGrip = 0
        lineRef = 0
        attachWas = nil
        fallingRound = false
        let impact = min(vel.length, 1400)
        // Down off a line — a hang, a dragline paying out, a swing — onto
        // something: the line may be left where it is, from up there to here.
        let offALine = webActive && rope.live
        let fromLine = mode == .dangling
        hurrying = false
        mode = .attached
        anchor = a
        lastLoopRect = nil
        walkDir = vel.dot(seg.dir) >= 0 ? 1 : -1
        // Coming straight down onto it, it keeps facing the way it already
        // does rather than flipping round as it lands.
        if abs(vel.dot(seg.dir)) < 20 {
            var forward = V2.angle(heading) * facing
            // Off a line — at the top of a climb, say, nose up against what
            // it is climbing onto — it goes the way its body comes round as
            // it brings its belly (and its feet) onto the surface, rather
            // than whichever way it happens to lean.
            if fromLine {
                let belly = V2(0, -1).rotated(by: heading)
                forward = forward.rotated(by: angleDelta(belly.angle, (-seg.normal).angle))
            }
            walkDir = forward.dot(seg.dir) >= 0 ? 1 : -1
        }
        // The feet take the ledge now, and the body carries on the way it
        // was going over them — down onto the legs, which take the blow and
        // give under it, and on along the ledge, which it leans into and
        // recovers from — rather than stopping dead in the air and sliding
        // to its spot. Whatever it is doing, the feet go where the ledge
        // is, not into it, and the body never sinks so far as to touch it.
        anchorValid = true
        anchorGlide = 9
        landedAt = t
        surfacePrev = nil
        if let here = map.resolve(a, cornerRadius: Spider.cornerRadius * config.scale) {
            let off = pos - here.pos
            let above = off.dot(here.normal)
            anchorPos = here.pos + here.tangent * off.dot(here.tangent)
            // Caught past where it stands (a fast one, or one that came
            // through from the far side): it lands at its standing height
            // and the blow is all in the speed it arrived with.
            lift.value = max(above, 0)
            if above < 0 { pos = anchorPos }
            // Into the ledge; a slow drift onto it still comes down at a
            // fair pace rather than hovering.
            let into = min(vel.dot(here.normal), -150 * config.scale)
            landDrop = above > 0
            lift.velocity = landDrop ? into : into * Spider.landAbsorb
            landStep = clamp(above / -into, 0.04, 0.08)
            skid.value = 0
            skid.velocity = clamp(vel.dot(here.tangent), -900, 900) * Spider.landAbsorb
        } else {
            anchorPos = pos
            landDrop = false
        }
        // (A climber steps up onto it; nothing lands hard.)
        if climbedUp { landStep = 0.16 }
        climbedOnto = climbedUp
        legFramePos = pos
        legFrameHeading = heading
        vel = .zero
        speed = 0
        // Stand on the ledge, facing the way it was going. The heading is left
        // to its spring, so the body swings down onto the surface rather than
        // snapping to it; the planted feet hold the ledge under the swing.
        headingTarget = seg.angle
        facing = walkDir
        faced()
        travelLocal = V2(1, 0)
        legMode = .planted
        // Splat onto the ledge, then spring back up.
        stretch.velocity = remap(impact, 100, 1200, 3, 12)
        crouch.velocity = remap(impact, 100, 1200, 2, 8)
        // Every foot goes straight for the ledge under it: a quick step
        // to a spot fixed in the world, planted before the body gets there.
        // One that is already at the ledge — or, coming in at an angle,
        // past it — is planted on it now.
        let normal = map.resolve(a, cornerRadius: Spider.cornerRadius * config.scale)?.normal ?? seg.normal
        for i in legs.indices {
            legs[i].footVel = .zero
            legs[i].swinging = false
            legs[i].lift = 0
            // (Nothing in reach yet — caught a way out from it — and the
            // step is to the ground itself, reached for as the body comes
            // down onto it: see `settleFoot`.)
            let near = reachableSpot(legs[i].rest, spread: true, leg: i)
            let spot = near.onGround ? near.point : groundFoot(legs[i].rest, spread: true)
            let foot = toWorld(legs[i].foot)
            let through = map.snapToEdge(foot, loopID: a.loopID).map { (foot - $0).dot(normal) < 1 } ?? false
            // (Only if it can reach its spot from here: one it cannot is
            // reached for as the body comes down — see `settleFoot`.)
            let hip = SpiderRenderer.rig(i, profile: SpiderRenderer.profileAmount(yaw: yaw), look: look).hip
            let reaches = spot.distance(to: hip) <= legLength(i) * Spider.reachShare + 0.5
            if through, reaches || climbedUp {
                // (Climbing up onto it, a foot that has hold of it already
                // keeps that hold, and steps to its spot from there.)
                if climbedUp, let touch = map.snapToEdge(foot, loopID: a.loopID) {
                    legs[i].foot = toLocal(touch)
                } else {
                    legs[i].foot = spot
                }
                legs[i].settle = -1
            } else {
                legs[i].settle = 0
                legs[i].swingFrom = legs[i].foot
                legs[i].settleTo = spot
            }
        }
        if !(offALine && leaveLineBehind(fastened: true)) { detachWeb(fade: true) }
        webPlan = []
        lingerUntil = -1
        pendingJump = nil
        queued = nil
        // A beat to get its feet under it before it decides anything.
        beginActivity(.idle, dur: 0.3)
        decisionIn = randRange(0.4, 1.0)
        if build != nil {
            // Spinning: landed on the other side of the corner, carry on;
            // anywhere else and the job is off.
            if let l = map.loop(a.loopID), l.kind == .screenBorder || l.kind == .menuBar { decisionIn = 0.2 }
            else { abandonBuild() }
        }
        if huntPounce {
            huntPounce = false
            pounceMark = nil
            snapAtPrey(reach: 14)
            // Come down right on top of it — dropped on it from above, say —
            // it is pinned under it: got, as surely as in the fangs.
            if caught == nil, let p = prey.first(where: { $0.state == .loose && $0.onSurface && $0.pos.distance(to: pos) < $0.kind.catchRadius * config.scale }) {
                catchPrey(p)
            }
            if caught == nil {
                decisionIn = 0.15
                if cursorHunt != .pouncing { remember(.huntMissed) }
            }
        }
        if cursorHunt == .pouncing {
            // Missed the pointer: a look about for where it went, and it
            // may try again soon.
            remember(.huntMissed, 0.3)
            endCursorHunt(nextIn: randRange(6, 14))
            beginActivity(.look, dur: randRange(0.9, 1.6))
            setEmote(.question, 1.1)
        }
        if impact > 800, caught == nil {
            setEmote(.surprise, 0.5)
            beginActivity(.shake, dur: 0.5)
        }
        if let c = caught, c.state == .caught, activity != .eat {
            // Landed with the catch: settle down to it.
            settleToMeal(c)
        }
        if joyLanding {
            // Down from a leap for joy: still fizzing with it.
            joyLanding = false
            if caught == nil, activity == .idle { queue(.wiggle, 0.8) }
        }
        if t < commotionUntil, activity == .idle {
            // Down from a start: still staring at what made it jump.
            queue(.look, max(commotionUntil - t - 0.3, 0.6))
            decisionIn = max(decisionIn, commotionUntil - t)
        }
    }

    /// `lineUp`: rather than a dragline from where it let go, a line shot
    /// up at the ceiling on the way down, to swing out on.
    private func detachAndFall(lineUp: Bool = false) {
        abandonBuild()
        lastLoopRect = nil
        let ledge = lineUp ? nil : ledgePoint()
        mode = .airborne
        air = .fall
        vel = V2(randRange(-30, 30), -20)
        airTime = 0
        noAttachFor = 0.05
        launchLoop = anchor.loopID
        legMode = .free
        queued = nil
        setEmote(.surprise, 0.6)
        startled.velocity = 7
        planFall(from: ledge, lineUp: lineUp)
    }

    /// The point on the edge under its feet, and the depth of what it is
    /// standing on: where a dragline is fastened. On a wall the line is
    /// fastened at the body's own line rather than on the edge, so hanging
    /// straight down from it does not put half of it off the screen.
    private func ledgePoint() -> (point: V2, depth: Int)? {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return nil }
        let seg = loop.segs[anchor.segIdx]
        // The edge must still be under its feet: a window that has moved
        // away or closed leaves nothing to fasten to.
        guard seg.point(at: anchor.t).distance(to: pos) < map.standoff * 2.5 else { return nil }
        let flat = seg.facing == .up || seg.facing == .down
        let point = flat ? pos - seg.normal * map.standoff : pos
        // Nor can it fasten to a stretch a window has come over.
        guard !loop.kind.onWindow || map.isVisible(point, depth: loop.depth) else { return nil }
        return (point, loop.depth)
    }

    /// Decides, as a fall begins, whether it will catch itself and where —
    /// never on the way down. A short drop is just a drop: it lands. A long
    /// one it takes on its dragline, fastened where it let go, paying it
    /// out as it falls and taking hold a third to a half of the way down,
    /// always well clear of whatever is below, so it never snatches at a
    /// line inches from the floor. With no ledge to fasten to, a line shot
    /// up at the ceiling does instead — when it is let go of in mid-air
    /// (`lineUp`), or as a last resort with nothing under it at all.
    private func planFall(from ledge: (point: V2, depth: Int)?, lineUp: Bool = false) {
        draglineCatchY = nil
        airShot = nil
        rappelAfterCatch = false
        pointerDrop = false
        guard config.webs, !inCinema, !hangOnly else { return }
        let screen = map.screenFrame(containing: pos)
        let lowest = (confine.map { max($0.minY, screen.minY) } ?? screen.minY) + 30 * config.scale
        // Moving sideways it will most likely clear whatever is right
        // under it, so only a straight drop counts that as its landing.
        let landingY = abs(vel.x) > 300 ? nil : map.landingBelow(pos, halfWidth: 24 * config.scale)
        let room = pos.y - (landingY ?? lowest)
        if let a = ledge {
            guard room > 240 * config.scale else { return }
            let drop = clamp(room * randRange(0.3, 0.55), 60, room - 150 * config.scale)
            draglineCatchY = pos.y - drop
            webAnchor = a.point
            webFromDepth = a.depth
            webActive = true
            webPlan = []
            webLen = max(20, pos.distance(to: a.point))
            webLenTarget = webLen
            prevHangLen = webLen
            rope.clear()
            return
        }
        // Nothing fastened: a shot at the ceiling. It takes a moment to
        // twist and the line a moment to get there, so there has to be
        // room for that and a proper swing under it. The mark is off to
        // one side, toward the middle of the screen, so the line comes
        // taut at an angle and swings it rather than just stopping it.
        guard lineUp || landingY == nil, room > 320 * config.scale else { return }
        // Tossed sideways, the mark is ahead of it — past where the toss
        // will have carried it by the time the line lands — so the swing
        // carries the motion on; otherwise toward the middle of the screen.
        let side: CGFloat = abs(vel.x) > 80 ? (vel.x > 0 ? 1 : -1) : (pos.x < screen.midX ? 1 : -1)
        let carried = clamp(vel.x * (Spider.airShotAim + Spider.airShotFlight), -400, 400)
        var mark: V2?
        for off in [carried + randRange(200, 360) * config.scale * side, carried, 0] where mark == nil {
            let x = clamp(pos.x + off, screen.minX + 40, screen.maxX - 40)
            mark = map.ceiling(above: V2(x, pos.y), maxRise: 900)
        }
        guard let c = mark else { return }
        let drop = clamp(room * randRange(0.35, 0.55), 60, room - 150 * config.scale)
        airShot = AirShot(target: c, depth: map.depth(at: c), catchY: pos.y - drop, began: t)
        webPlan = []
        rope.clear()
    }

    /// The dragline goes taut: from a fall to a hang, with a bounce on the
    /// line that matches how fast it was going.
    private func catchDragline() {
        let anchor = webAnchor, depth = webFromDepth
        let fallSpeed = max(0, -vel.y)
        let speed = vel.length
        // (An order given on the way down still stands.)
        let order = lineOrder
        attachWeb(at: anchor)
        lineOrder = order
        webFromDepth = depth
        draglineCatchY = nil
        webStyle = .hang
        swingPumping = false
        // Only a little more line, then a beat to gather itself.
        webLenTarget = min(webLen + randRange(0, 40 * config.scale), 780)
        bungee.velocity = clamp(fallSpeed * 0.35, 40, 320)
        stretch.velocity = 3
        webGrace = 0.6
        decisionIn = randRange(1.2, 2.4)
        if rappelAfterCatch || order != nil {
            // Stepped off the top of something to go down its line: on down.
            // It meant to, with its feet on the line braking, so the catch
            // is taken without much of a swing. (Told to, down or up.)
            let forPointer = pointerDrop
            rappelAfterCatch = false
            pointerDrop = false
            webAngleVel *= 0.3
            switch order {
            case .up?: webPlan = [.climbHome]
            case .down?: webPlan = [.toFloor]
            case .drop?: planDrop()
            case nil where forPointer:
                planPointerVisit()
            case nil:
                let screen = map.screenFrame(containing: webAnchor)
                planWeb(maxLen: max(40, webAnchor.y - (screen.minY + 30 * config.scale)))
            }
            if case .descend(let l)? = webPlan.first { webLenTarget = max(l, webLen) }
            decisionIn = order == nil ? randRange(0.3, 0.8) : 0
            return
        }
        planWeb(afterFall: true)
        // Taut at an angle and moving: that is a swing, not a stop — it
        // rides the arc and lets go near the top, or grabs what it passes.
        let alongArc = abs(webAngleVel) * webLen
        if abs(webAngle) > 0.2 || alongArc > 250, speed > 300, webLen > 90, !confined {
            webStyle = .swing
            swingFromLoop = ""
            swingPumping = false
            swingHalfSwings = 0
            lastSwingVelSign = 0
            swingPeak = abs(webAngle)
            swingReleaseAfter = chance(0.6) ? 1 : 2
            swingReleaseAt = randRange(0.55, 0.9)
            decisionIn = 99
            happy.velocity = 5
            if chance(0.5) { setEmote(.sparkle, 0.8) }
        }
    }

    // MARK: Dangling

    private func updateDangling(dt: CGFloat) {
        webGrace = max(0, webGrace - dt)

        // Just taken to the line: the body stays exactly where it is this
        // frame, and the line is measured from where the spinnerets are —
        // not from the body's middle — so nothing jumps as the pendulum
        // takes over.
        if hangOffFresh {
            // (Newly on a line it hangs from its spinnerets, whatever it
            // was doing on the last one.)
            climbLayout = 0
            lineGrip = 0
            lineRef = 0
            attachWas = spinnerets
            var off = silkAttachLocal()
            off.x *= mirrorSign
            hangOff = -off.rotated(by: heading) * config.scale
            hangOffFresh = false
            let r = (pos - hangOff) - webAnchor
            if r.length > 4 {
                webLen = max(20, r.length - bungee.value)
                webAngle = atan2(r.x, -r.y)
            }
            prevHangLen = webLen
            fallingRound = abs(webAngle) > 1.5
            mantle = nil
        }
        // Going over the top, or stepping down off its line onto something:
        // that has it.
        if mantle != nil {
            updateMantle(dt: dt)
            return
        }
        // How far round it is to face up the line: its nose toward the
        // anchor is 1, away from it (hanging head down) 0.
        let nose = V2(mirrorSign, 0).rotated(by: heading)
        upness = clamp((nose.dot((webAnchor - pos).normalized) + 1) / 2, 0, 1)
        // (Coming round it takes up the stance early, and rides round into
        // it; going back to hang, it lets go of the line as it turns away.)
        climbLayout = hangHeadUp ? smoothstep(clamp((upness - 0.35) / 0.4, 0, 1))
            : min(climbLayout, smoothstep(clamp((upness - 0.6) / 0.35, 0, 1)))
        // Turning end for end, it draws the line in to its middle before it
        // goes round, and turns about that; once round, it lets it back out
        // to where it hangs or climbs from. (Not falling round under a line
        // fastened beside it, nor swinging: then it hangs from its
        // spinnerets like a weight on a string.)
        let gripWant: CGFloat = flipSign != 0 && webStyle == .hang && !fallingRound ? 1 : 0
        lineGrip = clamp(lineGrip + clamp(gripWant - lineGrip, -dt / 0.3, dt / 0.22), 0, 1)
        reattach()

        // Keep the pendulum on the display: never pay out more thread than
        // there is room below the anchor, and never swing so wide it leaves
        // the sides. (Measured as it would be hanging from its spinnerets:
        // see `lineRef`.)
        let screen = map.screenFrame(containing: webAnchor)
        let margin = 30 * config.scale
        var maxLen = max(40, webAnchor.y - (screen.minY + margin))
        if hangOnly, let box = confine { maxLen = min(maxLen, max(40, webAnchor.y - (box.minY + margin))) }
        webLenTarget = min(webLenTarget, maxLen + lineRef)
        let swinging = webStyle == .swing
        if swinging {
            // A swing from low down starts on a line longer than the anchor
            // is high; it is what keeps the body off the floor *at this
            // angle* that bounds it, so the line is hauled in gradually as
            // it comes down through the arc, never snapped short.
            webLen = min(webLen, maxLen / max(cos(webAngle), 0.25) + lineRef)
        } else {
            webLen = min(webLen, maxLen + lineRef)
        }

        let maxSwing: CGFloat = swinging ? 1.5 : 1.1
        // Past the widest it can swing, it is eased back rather than
        // bounced: a hard reversal here is what a jolt looks like. (Just
        // taken to a line fastened beside or below it — stepping off the
        // top of a window — it first falls round under it, head over
        // heels, rather than being snapped round there.)
        if fallingRound, abs(webAngle) < maxSwing { fallingRound = false }
        var limitAcc: CGFloat = 0
        if abs(webAngle) > maxSwing, !fallingRound {
            let over = abs(webAngle) - maxSwing
            limitAcc = -(webAngle > 0 ? 1 : -1) * over * 60 - webAngleVel * 3
            webAngle = clamp(webAngle, -(maxSwing + 0.35), maxSwing + 0.35)
        }

        let lenBefore = webLen
        if swinging {
            webLen = approach(webLen, webLenTarget, 1.8, dt)
        } else {
            // Steady paces: it hauls itself up at a climbing speed and pays
            // out silk a little faster, easing off as it gets there — once
            // it is the right way up for it: turned head up to climb (a
            // small adjustment it makes as it hangs), head down to go down.
            let diff = webLenTarget - webLen
            var maxRate: CGFloat = diff < 0 ? (hurrying ? 110 : 62) : 125
            // (Nor any line paid out while it is still falling round under
            // where it is fastened: that would lift it. Nor either, turning
            // end for end, until it has the line back where it goes: its
            // feet are gathered round it at its middle till then.)
            let turning = fallingRound || lineGrip > 0 || (diff < 0 ? hangHeadUp && upness < 0.8 : upness > 0.3)
            if let e = entrance {
                // Its first entrance goes at its own, stately pace.
                maxRate = e.pace / config.scale
            } else if turning {
                maxRate = 0
            } else if diff < 0, upness > 0.5 {
                // Hand over hand it goes up in pulls: a surge as each front
                // leg heaves, easing as it reaches up for the next hold.
                maxRate *= 1 + 0.25 * sin((climbPhase - 0.3) * 4 * .pi)
            }
            maxRate *= config.scale
            webLen += clamp(diff * 4 * dt, -maxRate * dt, maxRate * dt)
        }
        // Paying out silk: a faint bob as each bit is let go.
        if webLen > lenBefore + 0.01 { stretch.value += sin(t * 14) * 0.004 }
        let g: CGFloat = 1950
        // Hanging, silk and air take the energy out of a swing quickly; a
        // proper swing is left to carry.
        // Just taken to its line in the box, it settles fast rather than
        // swinging in from wherever it was.
        let settling = hangOnly && t - hungSince < 4
        let damping: CGFloat = swinging ? 0.22 : (settling || fallingRound ? 6.0 : 1.6)
        let len = max(webLen + bungee.value, 20)
        var acc = -(g / len) * sin(webAngle) - webAngleVel * damping + limitAcc
        // The wind blows it out sideways on the end of its line, gust by
        // gust: it hangs at an angle in a steady one and swings as it comes
        // and goes. (Under something, the line is out of it.)
        if weatherOnIt, !sheltered { acc += windPush * cos(webAngle) / len }
        webAngleVel += acc * dt
        webAngle += webAngleVel * dt
        // Bouncing on the line stretches the body with it.
        stretch.value += bungee.velocity * 0.00025

        let dir = V2(sin(webAngle), -cos(webAngle))
        // The line ends where it is fastened to the body, not the body's
        // middle: hanging, the spinnerets; climbing, along its belly — so
        // the thread runs exactly along the line through the grips
        // whichever way up it is. The body hangs off that point and turns
        // about it; end for end, that is its middle (see `lineGrip`). (It
        // is always seen side on here, so the spinnerets never swap sides.)
        var attachOff = silkAttachLocal()
        attachOff.x *= mirrorSign
        hangOff = -attachOff.rotated(by: heading) * config.scale
        let newPos = webAnchor + dir * len + hangOff
        if dt > 0 { vel = (newPos - pos) / dt }
        pos = newPos

        // Sideways off the screen: the line snags and it swings back — but
        // only when it is heading further out, and only when the line hangs
        // from well inside the screen. With the anchor itself at the edge,
        // the bottom of the swing is already "out", and snagging there
        // would jerk it back and forth every frame at the bottom of the
        // line. Then it is simply let be.
        let anchorInside = webAnchor.x > screen.minX + margin + 20 && webAnchor.x < screen.maxX - margin - 20
        let headingOut = anchorInside && ((pos.x < screen.minX + margin && webAngleVel < 0)
            || (pos.x > screen.maxX - margin && webAngleVel > 0))
        if headingOut {
            webAngleVel = -webAngleVel * 0.5
            webAngle += webAngleVel * dt * 2
        }
        // A smoothed velocity for anything that reads direction off it —
        // the way it faces, the way its legs trail — so nothing flickers.
        swingVel = approach(swingVel, vel, 12, dt)

        legMode = .free
        crouch.step(to: 0, dt: dt)
        lift.step(to: 0, dt: dt)
        pitch.step(to: 0, dt: dt)
        lid.step(to: 0, dt: dt)
        activityTime += dt

        // Hangs holding the line: body along the thread, the hind legs
        // holding it above the spinnerets and the front ones hanging free.
        // Climbing is hand over hand — the feet stay put on the thread while
        // the body moves past them (see `updateLineLegs`).
        let alongThread = webAngle - .pi / 2                // direction from anchor to spider
        let moved = webLen - prevHangLen                    // + = descending
        prevHangLen = webLen
        hangDelta = abs(moved) < 40 * config.scale ? moved : 0

        if swinging {
            hangHeadUp = false
            flipSign = 0
            updateSwing(dt: dt, alongThread: alongThread, len: len)
            return
        }
        // Climbing, it turns to face up the line and hauls; once it has
        // stopped a while, or sets off back down, it lets itself back round
        // to hang head down. A real climb — a good stretch of line to haul
        // in — it turns to face up the thread for; a small adjustment it
        // makes as it hangs.
        let hauling = webLenTarget < webLen - 3
        let payingOut = webLenTarget > webLen + 3
        stillFor = hauling ? 0 : stillFor + dt
        let wasUp = hangHeadUp
        // (Up to the top of something it hangs down the face of — a window
        // it stepped off the top of — however short the way: it has to
        // climb over the lip there, head first.)
        if hauling, webLen - webLenTarget > 45 * config.scale
            || !hangHeadUp && webLenTarget < lineTop + 8 * config.scale && lipSpot() != nil {
            hangHeadUp = true
        } else if payingOut || stillFor > 1.6 {
            hangHeadUp = false
        }
        // End for end: head first round by its belly — the side its legs
        // hold the line on — to climb, and back the way it came to hang
        // again. Never the short way over its back, whichever is shorter.
        if hangHeadUp != wasUp { flipSign = hangHeadUp ? -facing : facing }
        // (Falling round under the line from above it, off the top of
        // something, it tips over head first, straight for hanging head
        // down, rather than following the line up and over.)
        let headDir = hangHeadUp ? alongThread + .pi : (fallingRound ? -.pi / 2 : alongThread)
        var target = headDir + (facing < 0 ? .pi : 0) + lineTilt + sin(t * 1.3) * 0.03
        if flipSign != 0 {
            // The heading's spring is led round a little ahead of the body
            // at a time — the long way, if the short way is the wrong way —
            // so it comes round at a steady, deliberate pace.
            var err = angleDelta(heading, target)
            if err * flipSign < 0, abs(err) > 1 { err += flipSign * 2 * .pi }
            if abs(err) < 0.3 {
                flipSign = 0
            } else if lineGrip < 0.5 {
                // It gathers the line in to its middle before it goes
                // round: until then it stays as it is.
                let up = upness > 0.5
                target = (up ? alongThread + .pi : alongThread) + (facing < 0 ? .pi : 0)
                    + (up ? facing * Spider.climbLean : -facing * 0.1) + sin(t * 1.3) * 0.03
            } else {
                target = heading + clamp(err, -Spider.turnLead, Spider.turnLead)
            }
        }
        headingTarget = target
        wag.step(to: t < lineJoyUntil ? 0.8 : 0, dt: dt)

        // A window has come over it on the line: straight up and out. Only
        // a window in front of the one it hung from counts — hanging down
        // the face of the very window it dropped off is the point. If the
        // window has come over the top of the line as well, there is
        // nothing up there to climb out onto: it swings off instead.
        if !map.isVisible(pos, depth: webFromDepth) {
            if homeIsOpen {
                webLenTarget = lineTop - 4 * config.scale
                webPlan = [.climbHome]
                lingerUntil = -1
                lineJoyUntil = 0
                // (Whatever it was told: it is getting out of there.)
                if lineOrder != .up { lineOrder = nil }
            } else if !leavingLostLine {
                leaveLostLine()
            }
        }

        // Curious about a pointer below it: pays out line to come and see.
        // (Not just after it was told where to go: the pointer is what told
        // it, and it stays where it was put.)
        var lingering = false
        if case .linger? = webPlan.first { lingering = true }
        if climbArrival == nil, lingering, lineOrder == nil, t - orderedAt > 12,
           config.approachCursor, cursorVel.length < 40, cursor.y < webAnchor.y - 60,
           abs(cursor.x - webAnchor.x) < 120 * config.scale, t - lastUserActivity < 6 {
            let want = clamp(webAnchor.y - cursor.y - 48 * config.scale, 30, maxLen)
            webLenTarget = approach(webLenTarget, want + lineRef, 1.5, dt)
        }

        if hangOnly {
            // Hanging in its box: a light, steady sway, driven the way a
            // draught would, at the line's own rhythm — never a swing.
            let omega = (1950 / max(len, 40)).squareRoot()
            swayPhase += dt * omega
            // Enough for a dozen pixels or so at the body, whatever the
            // length of line, coming and going slowly.
            let want = clamp(16 / max(len, 40), 0.05, 0.22) * (1 + 0.35 * sin(t * 0.13))
            webAngleVel += want * 1.6 * omega * cos(swayPhase) * dt
            decisionIn -= dt
            if decisionIn <= 0 { thinkHung() }
        } else if inCinema {
            // Caught on a line during the film: no antics, just down to
            // the floor and settle.
            webLenTarget = maxLen + lineRef
            webStyle = .hang
            swingPumping = false
            decisionIn = 99
        } else if entrance != nil {
            updateEntrance(dt: dt)
        } else if climbArrival == nil {
            decisionIn -= dt * config.liveliness
            // Being reeled about by hand (`decisionIn` pushed out): it does
            // as it is told and picks its plan up again after.
            if decisionIn <= 0 { thinkOnWeb() }
        }

        // (Not half-way through turning end for end, the line drawn in to
        // its middle: that is no way to take hold of anything. Nor making
        // its entrance, which goes down in front of everything.)
        guard webGrace <= 0, !hangOnly, lineGrip <= 0, entrance == nil else { return }

        // Climbing up and out (into the habitat): at the top, it is there.
        if let arrive = climbArrival, hangHeadUp || webLenTarget < 30, webLen < lineTop + 2 * config.scale {
            climbArrival = nil
            arrive()
            return
        }

        // On its way up and out, nothing on the way distracts it.
        guard climbArrival == nil else { return }

        // Reached the top: climb on.
        if webLen < lineTop + 8 * config.scale {
            // The line may be fastened to the lip of a shelf it stepped or
            // fell off: then the last bit is a pull-up over the edge, head
            // first — and hanging head down there, it comes round to climb
            // first, if it means to go up at all.
            if let lip = lipSpot() {
                if climbReady {
                    if beginMantle(onto: lip) { return }
                } else {
                    if !hangHeadUp, webLenTarget < lineTop + 8 * config.scale {
                        hangHeadUp = true
                        flipSign = -facing
                        stillFor = 0
                    }
                    return
                }
            }
            if let spot = map.nearestSpot(to: pos, within: 40 + map.standoff)
                ?? map.nearestSpot(to: webAnchor, within: 40 * config.scale + map.standoff) {
                land(on: spot.anchor, seg: spot.seg)
                return
            }
        }
        // Touched down on something below while barely swinging. Not while
        // it is hauling itself up: on its way somewhere it does not grab at
        // whatever it happens to pass. Nor the underside of anything: going
        // down, that is the bottom of a window it hangs in front of, and it
        // is no more touching that than the front. (Sent down, only a ledge
        // — something to stand on — will do.)
        if !hauling, abs(webAngleVel) < 0.7, abs(bungee.velocity) < 40,
           let spot = map.nearestSpot(to: pos, within: 22 * config.scale),
           spot.point.y < pos.y + 6, spot.seg.facing != .down,
           lineOrder != .down || spot.seg.facing == .up {
            // Head down onto the top of something: it steps down onto it.
            if spot.seg.facing == .up, upness < 0.25, lineGrip <= 0, webStyle == .hang, !fallingRound,
               beginMantle(onto: (spot.anchor, spot.seg), down: true) { return }
            land(on: spot.anchor, seg: spot.seg)
            return
        }
    }

    /// Hauling itself up and round to face up the line, all but done:
    /// ready to go over the top.
    private var climbReady: Bool {
        hangHeadUp && flipSign == 0 && lineGrip <= 0 && climbLayout > 0.95 && upness > 0.85 && webStyle == .hang
    }

    /// Where its line is fastened, if that is the top of something it is
    /// down the face of — a window it stepped off the top of, a shelf it fell
    /// from — rather than under: the spot on top it will have to climb over
    /// the lip onto.
    private func lipSpot() -> (anchor: Anchor, seg: Seg)? {
        guard let spot = map.nearestSpot(to: webAnchor, within: 40 * config.scale + map.standoff),
              spot.seg.facing == .up, (pos - spot.point).dot(spot.seg.normal) < -map.standoff * 0.5 else { return nil }
        return (spot.anchor, spot.seg)
    }

    // MARK: Over the top, and down onto it

    /// Up its line to the top of something it hangs from — a window it
    /// stepped off the top of, say — the line comes up over the lip, so it
    /// cannot simply arrive there. Its front legs reach over onto the top
    /// and pull it up until its waist is at the lip; it tips forward over
    /// the lip, belly first, as its hind legs, which have been pushing on the
    /// silk, come up over after it; and it stands up. All of it is laid out
    /// as it begins, so it goes from the climb to standing in one movement,
    /// and hands over to standing without a jolt.
    ///
    /// Coming down its line head first onto the top of something (`down`)
    /// is the same the other way about: its front legs, reaching down, take
    /// the ledge; it comes on down onto them, the rest of it pitching over
    /// belly first onto the ledge behind them; and its hind legs let go of
    /// the silk last and step down.
    private struct Mantle {
        let down: Bool
        let dur: CGFloat
        /// Where it will stand, and where that was as it began: a window
        /// moving under it carries the whole of it along.
        let spot: Anchor
        let spotAt: V2
        /// Where the line comes over the edge (going down, the edge under
        /// it); along the edge the way it goes (its nose's way, once it
        /// stands); and up off the edge.
        let lip: V2
        let fwd: V2
        let up: V2
        /// Its heading as it began, and how far round it tips.
        let h0: CGFloat
        let turn: CGFloat
        /// What it tips about, in sprite units (`mantleHinge`,
        /// `stepDownHinge`), and where that starts, comes up to at the lip,
        /// and ends up standing.
        let hinge: V2
        let hinge0: V2
        let hingeLip: V2
        let hingeEnd: V2
        /// How fast it was coming up the line (or down it), as the slope the
        /// rise (or the fall) starts at.
        let pace: CGFloat
        var t: CGFloat = 0
        var legs: [MantleLeg] = []
    }

    /// Somewhere a foot holds on going over the top: a spot in the world (on
    /// the top, or on the silk under the lip), or on the body (the silk
    /// along its belly, which comes round with it), or on the line, `silk`
    /// sprite units up it from where it leaves the body (which goes round
    /// with the line as the body pitches over under it). Off the top, the
    /// way the knee bends there, in sprite units.
    private struct MantleHold {
        var at: V2
        var onBody = false
        var onTop = false
        var silk: CGFloat?
        var bend = V2(0, -1)
    }

    /// A leg's part in it: its holds in turn, and when it goes from each to
    /// the next, as shares of the way through.
    private struct MantleLeg {
        var holds: [MantleHold]
        var moves: [(from: CGFloat, to: CGFloat)] = []
        /// The way round its hip it is going, on the way (see `roundHip`).
        var turn: CGFloat?
    }

    private var mantle: Mantle?
    /// The belly under its waist, between the hips, in sprite units: what it
    /// pulls up to the lip and tips over.
    private static let mantleHinge = V2(-3, -10)
    /// Stepping down, what it comes down onto its front legs about: the
    /// front of its belly, under the head.
    private static let stepDownHinge = V2(6, -10)
    /// How far past the lip it stands at the end, along the top, sprite units.
    private static let mantleAhead: CGFloat = 10
    /// How long going over the top takes, seconds; and stepping down.
    private static let mantleTime: CGFloat = 1.0
    private static let stepDownTime: CGFloat = 0.8

    /// Where it is `u` of the way over, as things stood when it began. The
    /// belly under its waist comes on up the line to the lip — at the pace
    /// it was climbing, easing to a stop there — and later rises off it as
    /// it stands up; meanwhile it tips forward about it, over the lip.
    /// Stepping down, the front of its belly comes on down to where it will
    /// stand — at the pace it was going down, easing to a stop — as the rest
    /// of it pitches over about it.
    private func mantleBody(_ m: Mantle, _ u: CGFloat) -> (pos: V2, heading: CGFloat) {
        func eased(_ r: CGFloat) -> CGFloat { m.pace * (r * r * r - 2 * r * r + r) + r * r * (3 - 2 * r) }
        let heading: CGFloat
        let hinge: V2
        if m.down {
            heading = m.h0 + m.turn * smoothstep(clamp((u - 0.05) / 0.8, 0, 1))
            hinge = m.hinge0 + (m.hingeEnd - m.hinge0) * eased(clamp(u / 0.8, 0, 1))
        } else {
            let stand = smoothstep(clamp((u - 0.5) / 0.5, 0, 1))
            heading = m.h0 + m.turn * smoothstep(clamp((u - 0.18) / 0.64, 0, 1))
            hinge = m.hinge0 + (m.hingeLip - m.hinge0) * eased(clamp(u / 0.45, 0, 1)) + (m.hingeEnd - m.hingeLip) * stand
        }
        return (hinge - bodyOffset(m.hinge, heading), heading)
    }

    /// A point on the sprite as an offset from its middle in the world, the
    /// body turned to `heading`.
    private func bodyOffset(_ l: V2, _ heading: CGFloat) -> V2 {
        V2(l.x * mirrorSign, l.y).rotated(by: heading) * config.scale
    }

    /// At the top of its line, under the top of what it hangs from: over the
    /// lip it goes. (`down`: at the bottom of its line, head down onto the
    /// top of something: down onto it it steps.) False if it cannot (not
    /// the right way round for it).
    private func beginMantle(onto lip: (anchor: Anchor, seg: Seg), down: Bool = false) -> Bool {
        let sc = config.scale
        let seg = lip.seg
        // Over the lip the way its belly faces — which, once it is standing
        // on top, is the way its nose points. (Down, head first, its belly
        // is the other way: it pitches over onto it.)
        let fwd = seg.dir * facing
        let belly = V2(0, -1).rotated(by: heading).dot(fwd)
        guard down ? belly < -0.3 : belly > 0.3 else { return false }
        let hl = down ? Spider.stepDownHinge : Spider.mantleHinge
        let hinge0 = toWorld(hl)
        // Up: a little way past the lip. Down: with the front of its belly
        // where it comes down, straight under it.
        let endT = down ? clamp(projectOnSegment(hinge0, seg.a, seg.b).t - facing * hl.x * sc, 0, seg.len)
            : clamp(lip.anchor.t + facing * Spider.mantleAhead * sc, 0, seg.len)
        let spot = Anchor(loopID: lip.anchor.loopID, segIdx: lip.anchor.segIdx, t: endT)
        guard let end = map.resolve(spot, cornerRadius: Spider.cornerRadius * sc) else { return false }
        let edge = seg.point(at: down ? endT : lip.anchor.t) - seg.normal * map.standoff
        // (Its belly comes up to just over the lip, never down on it.)
        let hingeLip = edge + fwd * (3 * sc) + seg.normal * (5 * sc)
        let h1 = end.tangent.angle
        let hingeEnd = end.pos + bodyOffset(hl, h1)
        let dur = down ? Spider.stepDownTime : Spider.mantleTime
        // (The pace it comes up — or down — at, as a slope of the ease.)
        let pace = down ? max(0, -vel.dot(seg.normal)) * 0.8 * dur / max(hinge0.distance(to: hingeEnd), 1)
            : max(0, vel.dot(seg.normal)) * 0.45 * dur / max(hinge0.distance(to: hingeLip), 1)
        var m = Mantle(down: down, dur: dur, spot: spot, spotAt: end.pos, lip: edge, fwd: fwd, up: seg.normal,
                       h0: heading, turn: angleDelta(heading, h1),
                       hinge: hl, hinge0: hinge0, hingeLip: down ? hingeEnd : hingeLip, hingeEnd: hingeEnd,
                       pace: clamp(pace, 0, 2.5))
        m.legs = planMantleLegs(m)
        mantle = m
        bungee.reset(0)
        webAngleVel = 0
        lineJoyUntil = 0
        regripLeg = -1
        return true
    }

    /// Each leg's part (see `MantleLeg`). The front legs reach over onto the
    /// top, out toward where they will stand — as far as they comfortably
    /// reach from where they will be — and on to it later. The
    /// hind legs push on the silk under the lip as it rises, until they can
    /// reach no further; take a fresh hold up by the belly, and come round
    /// with it as it tips over; and step up onto the top last. Stepping
    /// down, the front legs take the ledge the same way, first; the hind
    /// legs keep hold of the silk by the spinnerets until the body is most
    /// of the way over, and step down last.
    private func planMantleLegs(_ m: Mantle) -> [MantleLeg] {
        let sc = config.scale
        let step: CGFloat = 0.02
        let path = stride(from: CGFloat(0), through: 1.0001, by: step).map { mantleBody(m, $0) }
        func body(_ u: CGFloat) -> (pos: V2, heading: CGFloat) { path[min(Int((u / step).rounded()), path.count - 1)] }
        func world(_ l: V2, _ b: (pos: V2, heading: CGFloat)) -> V2 { b.pos + bodyOffset(l, b.heading) }
        func along(_ p: V2) -> CGFloat { (p - m.lip).dot(m.fwd) }
        // On the edge itself — near a window's corner, on the curve of it,
        // or round onto the next side — as standing puts its feet.
        let loop = map.loop(m.spot.loopID)
        func onEdge(_ p: V2) -> V2 { loop.map { footOnEdge(p, $0).point } ?? p }
        func onTop(_ x: CGFloat) -> V2 { onEdge(m.lip + m.fwd * x) }
        let done = body(1)
        // The order the front legs go over (or down) in, and the hind legs
        // step up (or down).
        let over: [Int: CGFloat] = m.down ? [0: 0, 4: 0.04, 1: 0.08, 5: 0.12] : [0: 0.02, 5: 0.06, 4: 0.1, 1: 0.14]
        let up: [Int: CGFloat] = m.down ? [2: 0.46, 6: 0.52, 3: 0.58, 7: 0.64] : [2: 0.44, 6: 0.5, 3: 0.57, 7: 0.64]
        var out: [MantleLeg] = []
        var letGo: [Int: CGFloat] = [:]
        for i in legs.indices {
            let hip = legs[i].hip
            let reach = lineReach(i) * sc
            let now = toWorld(legs[i].foot)
            let stand = onEdge(world(SpiderRenderer.rig(i, profile: 1, look: look).foot, done))
            // (Each knee bent as it was, to begin with.)
            let bend = legBend[i] ?? V2(0, -1)
            var leg = MantleLeg(holds: [MantleHold(at: now, bend: bend)])
            if m.down, over[i] == nil {
                // Holding the line just over the spinnerets, as it hung: it
                // keeps hold of it there as it pitches over, until it lets
                // go and steps down.
                let from = silkAttachWorld()
                let line = (webAnchor - from).length > 0.001 ? (webAnchor - from).normalized : m.up
                let s = max((now - from).dot(line) / sc, 2)
                leg.holds = [MantleHold(at: now, silk: s, bend: bend), MantleHold(at: stand, onTop: true)]
                leg.moves = [(up[i]!, up[i]! + 0.2)]
                out.append(leg)
                continue
            }
            // How far a spot is out of the leg's comfortable reach — knee
            // well bent, not folded right up — at worst, over a stretch of
            // the way: 0 if it never is.
            func strain(_ p: V2, from: CGFloat, to: CGFloat) -> CGFloat {
                var worst: CGFloat = 0
                for u in stride(from: from, through: to, by: 0.05) {
                    let d = world(hip, body(u)).distance(to: p)
                    worst = max(worst, d - reach * 0.75, reach * 0.3 - d)
                }
                return worst
            }
            if var a = over[i] {
                // (Sooner, if the body is about to come up past its hold and
                // crowd it: a foot never goes in through its own hip.)
                for u in stride(from: CGFloat(0), through: a, by: step)
                where world(hip, body(u)).distance(to: now) < reach * 0.45 {
                    a = max(0, u - 0.04)
                    break
                }
                // Well out over the top, toward where it will stand, so the
                // body comes up and over between them — but no further than
                // it comfortably reaches from where it is going to be.
                let b = a + 0.18
                var best = (x: along(stand) * 0.85, strain: CGFloat.greatestFiniteMagnitude)
                var x = best.x
                while x > -12 * sc {
                    let s = strain(onTop(x), from: (a + b) / 2, to: 1)
                    if s < best.strain - 0.01 { best = (x, s) }
                    if s <= 0 { break }
                    x -= sc
                }
                leg.holds.append(MantleHold(at: onTop(best.x), onTop: true))
                leg.moves.append((a, b))
                if abs(best.x - along(stand)) > 2 * sc {
                    let a2 = m.down ? 0.56 + a : 0.62 + (a - 0.03) * 0.8
                    leg.holds.append(MantleHold(at: stand, onTop: true))
                    leg.moves.append((a2, a2 + 0.16))
                }
            } else if let a2 = up[i] {
                // Pushing on the silk until the leg is at full stretch — or
                // until the end of the silk, drawn up along its belly, gets
                // to its foot.
                var go: CGFloat = 0.3
                for u in stride(from: CGFloat(0), through: 0.3, by: step) {
                    let b = body(u)
                    if world(hip, b).distance(to: now) > reach * 0.8
                        || world(climbHold, b).distance(to: m.lip) < now.distance(to: m.lip) + 3 * sc {
                        go = u
                        break
                    }
                }
                letGo[i] = go
                leg.holds.append(MantleHold(at: bellyLine(Spider.lineClimb[i] + 5), onBody: true))
                leg.moves.append((0, 0))
                leg.holds.append(MantleHold(at: stand, onTop: true))
                leg.moves.append((a2, a2 + 0.2))
            }
            out.append(leg)
        }
        // A fresh hold on the silk just before each would be at full stretch
        // — never two hind legs letting go of it at once.
        var last: CGFloat = -1
        for (i, go) in letGo.sorted(by: { $0.value < $1.value }) {
            let a = max(clamp(go - 0.08, 0.01, 0.3), last + 0.04)
            out[i].moves[0] = (a, a + 0.13)
            last = a
        }
        return out
    }

    /// Going over the top, each frame: the body where the pull-up has it,
    /// and the line taut from the lip to it.
    private func updateMantle(dt: CGFloat) {
        guard var m = mantle else { return }
        // Whatever it is getting onto is still there (moved, maybe): on with
        // it. Gone: back to hanging on its line.
        guard webActive, let here = map.resolve(m.spot, cornerRadius: Spider.cornerRadius * config.scale) else {
            mantle = nil
            hangOffFresh = true
            return
        }
        m.t += dt
        mantle = m
        let u = clamp(m.t / m.dur, 0, 1)
        let b = mantleBody(m, u)
        let now = b.pos + (here.pos - m.spotAt)
        if dt > 0 { vel = (now - pos) / dt }
        pos = now
        heading = b.heading
        headingTarget = heading
        headingVel = 0
        swingVel = approach(swingVel, vel, 12, dt)
        // Its hind legs off the silk along its belly, it lets that go back
        // to its spinnerets, taking up the last of what it had hauled in.
        if !m.down { climbLayout = 1 - smoothstep(clamp((u - 0.7) / 0.3, 0, 1)) }
        let attach = silkAttachWorld()
        webLen = max(attach.distance(to: webAnchor), 1)
        webLenTarget = webLen
        prevHangLen = webLen
        hangDelta = 0
        let d = toLocalDir(webAnchor - attach)
        lineDirLocal = d.length > 0.001 ? d.normalized : V2(1, 0)
        legMode = .free
        crouch.step(to: 0, dt: dt)
        lift.step(to: 0, dt: dt)
        pitch.step(to: 0, dt: dt)
        lid.step(to: 0, dt: dt)
        wag.step(to: 0, dt: dt)
        activityTime += dt
        if u >= 1 { finishMantle() }
    }

    /// Over the top (or down off its line) and on its feet: it is standing
    /// there now.
    private func finishMantle() {
        guard let m = mantle, let seg = map.seg(m.spot) else { mantle = nil; return }
        mantle = nil
        vel = .zero
        land(on: m.spot, seg: seg)
        // It stepped on; it did not come down on it: none of a landing's
        // give, and the knees come over to standing as they do off a climb.
        climbedOnto = true
        lift.value = 0
        lift.velocity = 0
        landDrop = false
        skid.value = 0
        skid.velocity = 0
        stretch.velocity = 0.6
        crouch.velocity = 0.8
    }

    /// The legs going over the top (see `planMantleLegs`): each foot at its
    /// hold, or on its way round its hip from one to the next, lifted clear
    /// — up over the lip onto the top, out off the silk.
    private func updateMantleLegs() {
        guard var m = mantle, m.legs.count == legs.count else { return }
        let u = clamp(m.t / m.dur, 0, 1)
        let shift = map.resolve(m.spot, cornerRadius: Spider.cornerRadius * config.scale).map { $0.pos - m.spotAt } ?? .zero
        let upLocal = toLocalDir(m.up)
        let from = silkAttachWorld()
        let line = (webAnchor - from).length > 0.001 ? (webAnchor - from).normalized : m.up
        func local(_ h: MantleHold) -> V2 {
            if let s = h.silk { return toLocal(from + line * (s * config.scale)) }
            return h.onBody ? h.at : toLocal(h.at + shift)
        }
        // A knee on top is up off it; on the silk, bent out from it, as
        // climbing or hanging — until, tipping over, that would put it down
        // through the edge: then up, as on top.
        let tipped = smoothstep(clamp((u - 0.3) / 0.25, 0, 1))
        func bend(_ h: MantleHold) -> V2 {
            h.onTop ? upLocal : h.onBody || h.silk != nil ? h.bend * (1 - tipped) + upLocal * tipped : h.bend
        }
        for i in legs.indices {
            var plan = m.legs[i]
            var stage = 0
            for (j, mv) in plan.moves.enumerated() where u >= mv.to { stage = j + 1 }
            var foot: V2
            var knee: V2
            var lift: CGFloat = 0
            let hip = legs[i].hip
            if stage < plan.moves.count, u > plan.moves[stage].from {
                let mv = plan.moves[stage]
                let e = clamp((u - mv.from) / max(mv.to - mv.from, 0.01), 0, 1)
                let s = easeInOutSine(e)
                let a = plan.holds[stage], b = plan.holds[stage + 1]
                foot = Spider.roundHip(local(a), local(b), hip: hip, s, turn: &plan.turn, fold: 0.35)
                lift = sin(e * .pi)
                foot = foot + (b.onTop ? upLocal * 4 : V2(0, -3)) * lift
                knee = bend(a) * (1 - s) + bend(b) * s
            } else {
                plan.turn = nil
                foot = local(plan.holds[min(stage, plan.holds.count - 1)])
                knee = bend(plan.holds[min(stage, plan.holds.count - 1)])
            }
            // (Never out past what the leg reaches — nor, on its way, folded
            // right up in by the hip, where the knee has nowhere to go.)
            let most = lineReach(i) * 0.98, least = lineReach(i) * (lift > 0 ? 0.35 : 0)
            let off = foot - hip
            if off.length > most { foot = hip + off.normalized * most }
            if off.length < least, off.length > 0.001 { foot = hip + off.normalized * least }
            legs[i].foot = foot
            legs[i].footVel = .zero
            legs[i].lift = lift
            legs[i].swinging = lift > 0
            legs[i].settle = -1
            legBend[i] = knee.length > 0.01 ? knee.normalized : upLocal
            legBones[i] = Spider.lineBones(i)
            m.legs[i] = plan
        }
        mantle = m
    }

    /// The swing proper: the body flies along the arc, and it lets go on the
    /// way up, or grabs whatever it swings past.
    private func updateSwing(dt: CGFloat, alongThread: CGFloat, len: CGFloat) {
        let sign: CGFloat = webAngleVel >= 0 ? 1 : -1
        if lastSwingVelSign != 0, sign != lastSwingVelSign {
            swingHalfSwings += 1
            swingPeak = max(abs(webAngle), 0.15)
        }
        lastSwingVelSign = sign

        // A weight on a string: it hangs in line with the thread, head to the
        // ground, and the body trails the line a little through each swing.
        // It keeps the same side to you the whole way — turning round on a
        // thread is a half-roll of the body, and doing that at every end of
        // the arc is what made a swing look like a tumble.
        let lag = clamp(-webAngleVel * 0.08, -0.2, 0.2)
        headingTarget = alongThread + lag + (facing < 0 ? .pi : 0) + lineTilt
        wag.step(to: 0.3, dt: dt)

        // Working the swing up: nothing comes from nowhere. Each pass it
        // pumps — kicking its legs and shifting its weight in time with the
        // motion — and the arc grows a little every half-swing until it is
        // as big as it wants, or it gives up trying.
        if swingPumping {
            let reached = swingPeak >= swingTargetPeak || abs(webAngle) >= swingTargetPeak
            if reached || t > swingPumpUntil {
                swingPumping = false
                swingHalfSwings = 0
                swingReleaseAfter = chance(0.5) ? 1 : 2
            } else {
                let w = (1950 / max(len, 40)).squareRoot()
                webAngleVel += sign * 0.30 * w * dt
            }
            return
        }

        guard webGrace <= 0 else { return }

        // Something within reach as it swings past: grab it — but not the
        // ledge it just left, until it has swung properly.
        if vel.length > 150,
           let spot = map.nearestSpot(to: pos, within: 24 * config.scale,
                                      excluding: swingHalfSwings < 2 ? swingFromLoop : nil),
           (spot.point - pos).dot(vel) > 0 {
            land(on: spot.anchor, seg: spot.seg)
            happy.velocity = 4
            return
        }

        // Let go near the top of the swing, on the way up, after enough
        // swings to have made something of it.
        let risingAway = webAngle * webAngleVel > 0
        if swingHalfSwings >= swingReleaseAfter, risingAway, abs(webAngle) > swingPeak * swingReleaseAt, abs(webAngle) > 0.12 {
            releaseSwing()
            return
        }
        // It has run out of swing: just hang there instead.
        let dead = abs(webAngleVel) < 0.08 && abs(webAngle) < 0.08 && !swingPumping
        if swingHalfSwings > 7 || dead || (swingHalfSwings >= 2 && abs(webAngleVel) < 0.35 && abs(webAngle) < 0.15) {
            webStyle = .hang
            webLenTarget = webLen
            prevHangLen = webLen
            decisionIn = randRange(0.6, 1.4)
        }
    }

    /// From a hang: works itself up into a real swing, pass by pass, and
    /// lets go at the top once it is big enough.
    private func workUpSwing() {
        guard mode == .dangling, webActive else { return }
        webStyle = .swing
        swingFromLoop = ""
        swingPumping = true
        swingTargetPeak = randRange(0.8, 1.25)
        swingPumpUntil = t + 11
        swingPeak = 0
        webAngleVel += (chance(0.5) ? 1 : -1) * 0.2
        swingHalfSwings = 0
        lastSwingVelSign = 0
        swingReleaseAfter = chance(0.5) ? 1 : 2
        swingReleaseAt = randRange(0.55, 0.9)
        webGrace = 0.4
        decisionIn = 99
        happy.velocity = 5
    }

    private func releaseSwing() {
        if !leaveLineBehind(fastened: false) { detachWeb(fade: true) }
        mode = .airborne
        air = .jump
        airTime = 0
        noAttachFor = 0.1
        launchLoop = ""
        vel = vel.clampedLength(1500)
        legMode = .free
        stretch.velocity = 3
        if chance(0.5) { setEmote(.sparkle, 0.7) }
        happy.velocity = 5
    }

    /// Looks for something up ahead to hang a line from, and if there is
    /// one, takes aim. Returns false if there is nowhere to swing to.
    private func startSwing() -> Bool {
        guard mode == .attached, !inCinema, !confined, let loop = map.loop(anchor.loopID),
              anchor.segIdx < loop.segs.count else { return false }
        let seg = loop.segs[anchor.segIdx]
        guard let target = swingLine(from: pos, on: anchor.loopID, forward: seg.dir * walkDir) else { return false }
        shotTarget = target
        shotPurpose = .swing
        shotProgress = 0
        queued = nil
        beginActivity(.shoot, dur: 0.28)
        return true
    }

    /// Where a line shot `forward` from `from` (standing on loop `loopID`)
    /// would fasten for a good swing, if anywhere.
    private func swingLine(from origin: V2, on loopID: String, forward: V2) -> V2? {
        let screen = map.screenFrame(containing: origin)
        // From the floor there is nothing to swing down from, so the line has
        // to go out well ahead and it reels in hard; from up high, a steeper
        // line gives a proper drop.
        let onFloor = origin.y - screen.minY < 80
        var best: (score: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) where spot.loop.id != loopID || spot.loop.kind == .screenBorder {
            let a = spot.point - spot.seg.normal * map.standoff        // the edge itself
            let d = a - origin
            let rise = d.y
            guard rise > (onFloor ? 140 : 90), rise < 620 else { continue }
            let ahead = d.dot(forward)
            guard ahead > rise * (onFloor ? 0.7 : 0.25), ahead < rise * 1.05 else { continue }
            // The bottom of the arc, once it has reeled in a little, must stay
            // on the display, and so must the far end of the swing.
            let len = d.length
            guard a.y - len * (onFloor ? 0.72 : 0.85) > screen.minY + 2 else { continue }
            guard a.x + len < screen.maxX + 40, a.x - len > screen.minX - 40 else { continue }
            // Longer lines and wider angles make the better swings.
            var score = spot.loop.kind.appeal * remap(len, 110, 700, 0.7, 1.25) * (0.5 + ahead / rise)
            score *= randRange(0.7, 1.3)
            if best == nil || score > best!.score { best = (score, a) }
        }
        return best?.point
    }

    /// The line has caught: let go of the ledge and push off into the swing.
    private func launchSwing() {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else {
            beginActivity(.idle, dur: 0.1)
            return
        }
        let seg = loop.segs[anchor.segIdx]
        let forward = seg.dir * walkDir
        webAnchor = shotTarget
        webActive = true
        webFromDepth = map.occluders.filter { $0.rect.insetBy(dx: -4, dy: -4).contains(shotTarget.point) }.map(\.depth).min() ?? Int.max
        webStyle = .swing
        let r = pos - webAnchor
        webLen = max(30, r.length)
        // Reels in as it goes, which is what makes a swing gather speed; hard,
        // if it set off from the floor and has to climb clear of it.
        let screen = map.screenFrame(containing: pos)
        let onFloor = pos.y - screen.minY < 80
        webLenTarget = webLen * (onFloor ? randRange(0.66, 0.74) : randRange(0.8, 0.88))
        swingFromLoop = anchor.loopID
        webAngle = atan2(r.x, -r.y)
        let tangent = V2(cos(webAngle), sin(webAngle))
        let push = forward * randRange(380, 560) + seg.normal * 120
        webAngleVel = push.dot(tangent) / webLen
        vel = push
        swingHalfSwings = 0
        lastSwingVelSign = 0
        swingPeak = 0
        // The push-off starts it; if that is not a big enough arc it pumps
        // the rest of the way up before it lets go.
        swingPumping = true
        swingTargetPeak = randRange(0.85, 1.25)
        swingPumpUntil = t + 7
        swingReleaseAfter = chance(0.55) ? 1 : (chance(0.6) ? 2 : 3)
        swingReleaseAt = randRange(0.55, 0.9)
        mode = .dangling
        hangOffFresh = true
        hangHeadUp = false
        flipSign = 0
        legMode = .free
        anchorValid = false
        activity = .idle
        queued = nil
        webGrace = 0.5
        decisionIn = 99
        stretch.velocity = 4
        happy.velocity = 3
    }

    /// Draws up what it will do on the line it is about to drop on.
    private func planWeb(maxLen: CGFloat) {
        let play = personality.playfulness
        let first = clamp(randRange(150, 430), 40, maxLen)
        webPlan = [.descend(first), .linger(randRange(3, 9) * lerp(1.3, 0.7, personality.energy))]
        // Sometimes a second look, a little further down or back up.
        if chance(0.35) {
            let second = clamp(first + randRange(-160, 200), 40, maxLen)
            if abs(second - first) > 50 { webPlan += [.descend(second), .linger(randRange(2, 6))] }
        }
        let roll = CGFloat.random(in: 0...1)
        let floorClose = maxLen < 760
        if roll < 0.42 || confined {
            webPlan.append(.climbHome)
        } else if roll < 0.66, floorClose {
            webPlan.append(.toFloor)
        } else if roll < 0.66 + play * 0.2, first > 90 {
            webPlan.append(.swing)
        } else if roll < 0.9 {
            webPlan.append(.jumpOff)
        } else {
            webPlan.append(.climbHome)
        }
    }

    /// What it does once its dragline has caught it: a moment to collect
    /// itself where it hangs, then one thing — back up the line to where it
    /// fell from, if that is still there and in the open; else on down to
    /// the floor, or a leap to something else. No dithering up and down
    /// the line first: the fall was enough excitement.
    private func planWeb(afterFall: Bool) {
        let screen = map.screenFrame(containing: webAnchor)
        let maxLen = max(40, webAnchor.y - (screen.minY + 30 * config.scale))
        webPlan = [.linger(randRange(1.5, 4.0))]
        lingerUntil = -1
        if homeIsOpen, chance(0.6) {
            webPlan.append(.climbHome)
        } else if maxLen < 760 {
            webPlan.append(.toFloor)
        } else {
            webPlan.append(.jumpOff)
        }
    }

    /// Whether the top of the line is somewhere it could take hold of: an
    /// edge that is still there, and not behind another window.
    private var homeIsOpen: Bool {
        guard map.isVisible(webAnchor, depth: webFromDepth) else { return false }
        return map.nearestSpot(to: webAnchor, within: 40 * config.scale + map.standoff) != nil
    }

    /// Already on its way off a line whose top has gone.
    private var leavingLostLine: Bool {
        switch webPlan.first {
        case .swingOff?, .toFloor?: return true
        default: return false
        }
    }

    /// The top of the line is no longer anywhere to climb out onto — the
    /// window it hung from has gone, or another has come over it. Rather
    /// than hang under nothing, it pays out enough line to swing on, works
    /// up a swing and lets go. With no room below for a swing, it goes on
    /// down to the floor and steps off there.
    private func leaveLostLine() {
        let screen = map.screenFrame(containing: webAnchor)
        let maxLen = max(40, webAnchor.y - (screen.minY + 30 * config.scale))
        if maxLen >= 120, !confined {
            let len = clamp(max(webLen - lineRef, 170 * config.scale), 110, min(maxLen, 420))
            webPlan = [.swingOff(len)]
        } else {
            webPlan = [.toFloor]
        }
        // (Nothing up there to be told to climb to any more.)
        lineOrder = nil
        lingerUntil = -1
        lineJoyUntil = 0
        decisionIn = 0
    }

    /// Works through the plan. Called every frame on a hang; it only ever
    /// does one thing at a time and moves on when that thing is done.
    private func thinkOnWeb() {
        if debugCalm { return }
        if webPlan.isEmpty {
            let screen = map.screenFrame(containing: webAnchor)
            planWeb(maxLen: max(40, webAnchor.y - (screen.minY + 30 * config.scale)))
        }
        guard let step = webPlan.first else { return }
        switch step {
        case .descend(let l):
            // (The plan's lengths are as it hangs from its spinnerets; see
            // `lineRef`.)
            webLenTarget = l + lineRef
            if abs(webLen - webLenTarget) < 4 {
                webPlan.removeFirst()
                lingerUntil = -1
                // (Told to go down off its ledge: it has; the hang is its own.)
                if lineOrder == .drop { lineOrder = nil }
            }
        case .linger(let d):
            if lingerUntil < 0 {
                lingerUntil = t + d
                lingerNext = t + randRange(0.8, 2.0)
                // Arriving: a little bounce on the line, if it is that sort.
                if chance(personality.playfulness * 0.6) { bungee.velocity = randRange(120, 220) * (chance(0.5) ? 1 : -1) }
            }
            // Hanging there, looking about: the odd shift of weight sets it
            // swaying, a note or a sparkle now and then — nothing sudden.
            if t > lingerNext {
                lingerNext = t + randRange(1.5, 3.5)
                if chance(0.5) { webAngleVel += randRange(-0.12, 0.12); happy.velocity = 2 }
                else if chance(0.3), emote == .none { setEmote(chance(0.6) ? .sparkle : .note, 0.9) }
            }
            if t > lingerUntil { webPlan.removeFirst(); lingerUntil = -1 }
            // Something worth chasing has turned up (a meal, the red dot):
            // the hang is over — down to the floor if it is below, else home.
            if caught == nil, let mark = laser ?? quarry()?.pos {
                let screen = map.screenFrame(containing: webAnchor)
                let below = mark.y < webAnchor.y - 60 && webAnchor.y - (screen.minY + 30 * config.scale) < 760
                webPlan = [below ? .toFloor : .climbHome]
                lingerUntil = -1
            }
        case .climbHome:
            webLenTarget = lineTop - 4 * config.scale
            // Reached the top: the landing check below takes it from here —
            // unless there is nothing there to take hold of any more (the
            // window has gone, or something has come over it): then down
            // it goes instead, rather than hanging under nothing.
            if webLen < lineTop + 8 * config.scale, !homeIsOpen { leaveLostLine() }
        case .toFloor:
            webLenTarget = floorLen
            // Down as far as the line goes and nothing to step onto: back up.
            // (Told to go down, it waits there longer before it gives up.)
            if webLen > floorLen - 3, abs(webAngleVel) < 0.3 {
                if floorWait < 0 { floorWait = t }
                if t - floorWait > (lineOrder == .down ? 6 : 2.5) {
                    webPlan = [.climbHome]
                    lineOrder = nil
                }
            } else {
                floorWait = -1
            }
        case .swing:
            webPlan.removeFirst()
            if webLen > 90, !confined { workUpSwing() } else { webPlan = [.climbHome] }
        case .swingOff(let l):
            webLenTarget = l + lineRef
            if abs(webLen - webLenTarget) < 4 {
                webPlan.removeFirst()
                if webLen > 90, !confined { workUpSwing() } else { webPlan = [.toFloor] }
            }
        case .jumpOff:
            webPlan.removeFirst()
            if let spot = bestJumpSpot(from: pos, exclude: ""), let launch = ballistic(from: pos, to: spot.point) {
                if !leaveLineBehind(fastened: false) { detachWeb(fade: true) }
                mode = .airborne
                air = .jump
                airTime = 0
                noAttachFor = 0.08
                vel = launch
            } else {
                webPlan = [.climbHome]
            }
        }
    }

    private func attachWeb(at p: V2) {
        tumbleVel = 0
        draglineCatchY = nil
        airShot = nil
        lineOrder = nil
        webAnchor = p
        webActive = true
        webFromDepth = map.occluders.filter { $0.rect.insetBy(dx: -4, dy: -4).contains(p.point) }.map(\.depth).min() ?? Int.max
        webPlan = []
        lingerUntil = -1
        // The pendulum is the line to its spinnerets, where it hangs from —
        // measured there from the start, so the swing it is caught into is
        // the one it goes on to have. (Measured from the body's middle, a
        // line fastened off to one side would set it swinging hard.)
        let r = toWorld(spinnerets) - p
        webLen = max(28, r.length)
        webLenTarget = min(webLen + randRange(0, 120), 780)
        webAngle = atan2(r.x, -r.y)
        let tangent = V2(-r.y, r.x).normalized
        webAngleVel = vel.dot(tangent) / max(webLen, 1)
        mode = .dangling
        hangOffFresh = true
        legMode = .free
        stretch.velocity = -3
        decisionIn = randRange(0.8, 2.0)
        webGrace = 0.5
        bungee.reset(0)
        prevHangLen = webLen
        hangHeadUp = false
        flipSign = 0
        stillFor = 0
        // Caught at speed, the line becomes a swing rather than a stop —
        // except in its box, where it just hangs.
        if abs(vel.x) > 320 && webLen > 90 && !confined {
            webStyle = .swing
            swingFromLoop = ""
            swingPumping = false
            swingHalfSwings = 0
            lastSwingVelSign = 0
            swingReleaseAfter = chance(0.6) ? 1 : 2
            swingReleaseAt = randRange(0.55, 0.9)
            decisionIn = 99
        } else {
            webStyle = .hang
        }
    }

    private func updateWeb(dt: CGFloat) {
        guard webActive else { return }
        let overstretched = pos.distance(to: webAnchor) > webLen * 2.2 + 200
        // (Its entrance's line is fastened up out of sight, off the top.)
        if overstretched || (!map.isOnScreen(webAnchor, slack: 60) && entrance == nil) {
            detachWeb(fade: true)
            if mode == .dangling {
                mode = .airborne
                air = .fall
                airTime = 0
                noAttachFor = 0.05
                setEmote(.surprise, 0.5)
            }
        }
    }

    private func detachWeb(fade: Bool) {
        hurrying = false
        draglineCatchY = nil
        airShot = nil
        lineOrder = nil
        if webActive && fade {
            // A slow fade, so the let-go line can be seen drifting down.
            webAlpha = Spring(0.7, stiffness: 14, damping: 7.6)
        }
        webActive = false
    }

    private func dropOnWeb() {
        guard config.webs else { return }
        // Anchor the thread on the edge it is gripping, not in mid-air: the
        // spinnerets dabbed on it right where they are, so it lets go and
        // swings down head first about them.
        var a = pos
        webFromDepth = Int.max
        var onTop = false
        if let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count {
            let seg = loop.segs[anchor.segIdx]
            let along = clamp((toWorld(spinnerets) - seg.a).dot(seg.dir), 0, seg.len)
            a = seg.point(at: along) - seg.normal * map.standoff
            webFromDepth = loop.depth
            onTop = seg.facing == .up
        }
        webAnchor = a
        webActive = true
        if onTop {
            // Standing on top of something there is nothing over the drop to
            // hang from: it steps off the edge on its dragline, fastened
            // where it stood, and lets the line take it a short way down;
            // then on down it goes, as from under a ledge.
            let screen = map.screenFrame(containing: pos)
            let room = pos.y - (screen.minY + 30 * config.scale)
            mode = .airborne
            air = .fall
            airTime = 0
            noAttachFor = 0.3
            launchLoop = anchor.loopID
            vel = V2.angle(heading) * facing * 25 + V2(0, 60)
            legMode = .free
            queued = nil
            webPlan = []
            webLen = max(20, pos.distance(to: a))
            webLenTarget = webLen
            prevHangLen = webLen
            rope.clear()
            draglineCatchY = pos.y - clamp(room * 0.4, 30 * config.scale, 80 * config.scale)
            rappelAfterCatch = true
            return
        }
        webLen = 22
        webLenTarget = randRange(150, 430)
        webAngle = 0
        webAngleVel = randRange(-0.15, 0.15)
        webStyle = .hang
        bungee.reset(0)
        prevHangLen = webLen
        hangHeadUp = false
        flipSign = 0
        stillFor = 0
        mode = .dangling
        hangOffFresh = true
        legMode = .free
        queued = nil
        decisionIn = randRange(0.3, 0.8)
        webGrace = 0.9
        let screen = map.screenFrame(containing: a)
        if lineOrder == .drop {
            planDrop()
        } else {
            planWeb(maxLen: max(40, a.y - (screen.minY + 30 * config.scale)))
        }
        if case .descend(let l)? = webPlan.first { webLenTarget = l }
    }

    /// Told to go down off its ledge: half way down to whatever is below it
    /// — the next thing it could stand on, or the floor — and there it
    /// hangs a good while before it goes about its own business again.
    private func planDrop() {
        let screen = map.screenFrame(containing: webAnchor)
        let maxLen = max(40, webAnchor.y - (screen.minY + 30 * config.scale))
        planWeb(maxLen: maxLen)
        let then = webPlan.last ?? .climbHome
        // (What is below, as the height of its edge; hanging head down its
        // middle is a body's length under the line's end, the spinnerets.)
        let below = map.landingBelow(webAnchor - V2(0, 30 * config.scale), halfWidth: 24 * config.scale)
            .map { $0 - map.standoff } ?? screen.minY
        let half = (webAnchor.y - below) / 2 + spinnerets.x * config.scale
        webPlan = [.descend(clamp(half, 40 * config.scale, maxLen)), .linger(randRange(10, 16)), then]
        lingerUntil = -1
    }

    /// As far down its line as it can go: its spinnerets just clear of the
    /// bottom of the screen (as it would read hanging from them; see
    /// `lineRef`).
    private var floorLen: CGFloat {
        let screen = map.screenFrame(containing: webAnchor)
        return max(40, webAnchor.y - (screen.minY + 30 * config.scale)) + lineRef
    }

    // MARK: Hammock

    /// Where the hammock goes on the screen it is on: tucked into a top
    /// corner, under the menu bar.
    private func hammockRect(left: Bool) -> CGRect {
        let f = map.screenFrame(containing: pos)
        let top = map.menuBarBottom(for: f) ?? f.maxY
        let sc = max(config.scale, 0.7)
        let w = 190 * sc, h = 130 * sc
        return CGRect(x: left ? f.minX : f.maxX - w, y: top - h, width: w, height: h)
    }

    /// The spot on the screen border it steps in from: on the side wall,
    /// level with the middle of the sac.
    private func hammockDoor(_ h: Hammock) -> V2 {
        V2(h.left ? h.rect.minX + map.standoff : h.rect.maxX - map.standoff, h.wallAnchor.y - 4)
    }

    private func nestCentre(_ h: Hammock) -> V2 {
        h.bed + V2(0, 12 * config.scale)
    }

    /// Set off for the hammock. Building one first picks the nearer corner.
    private func goHome(_ goal: HomeGoal) {
        guard !inCinema, !confined, !inHabitat else { return }
        if goal == .build, hammock == nil {
            let f = map.screenFrame(containing: pos)
            let left = pos.x < f.midX
            hammock = Hammock(left: left, rect: hammockRect(left: left), progress: 0, damage: 0)
            wantsSleepAfterBuild = chance(0.6)
        }
        guard hammock != nil || goal == .corner else { return }
        homing = goal
        homingSince = t
        queued = nil
        pursueHome()
    }

    /// One step of the journey: walk if it is on the screen border, jump
    /// to it if it is not, and step in when it gets there.
    /// The bottom corner nearer to it, a little in from the wall.
    private func hideawaySpot() -> V2 {
        let f = map.screenFrame(containing: pos)
        let left = pos.x < f.midX
        let inset = map.standoff + 34 * config.scale
        return V2(left ? f.minX + inset : f.maxX - inset, f.minY + map.standoff)
    }

    private func pursueHome() {
        guard let goal = homing else { return }
        let door: V2
        if goal == .corner {
            door = hideawaySpot()
        } else {
            guard let h = hammock else { homing = nil; return }
            door = hammockDoor(h)
        }
        if pos.distance(to: door) < 40 * config.scale {
            homing = nil
            switch goal {
            case .build: beginBuilding()
            case .sleep:
                // Torn: it mends it before it will lie in it.
                if let h = hammock, h.damage > 0.05 { beginMend(thenSleep: true) } else { enterNest() }
            case .mend: beginMend(thenSleep: false)
            case .corner:
                turnTo(pos.x < door.x ? 1 : -1, then: .rest, for: 3)
                queue(.sleep, randRange(40, 90))
            }
            return
        }
        guard let loop = map.loop(anchor.loopID) else { return }
        if loop.kind == .screenBorder || loop.kind == .menuBar {
            walkToward(door)
            activityDur = max(activityDur, 3.5)
            return
        }
        // Elsewhere: leap onto the screen border, as near the door as it can.
        var best: (d: CGFloat, p: V2)?
        for spot in map.sampleSpots(spacing: 40) where spot.loop.kind == .screenBorder {
            let d = spot.point.distance(to: door)
            guard spot.point.distance(to: pos) > 60, ballistic(from: pos, to: spot.point) != nil else { continue }
            if best == nil || d < best!.d { best = (d, spot.point) }
        }
        if let b = best {
            startJump(to: b.p)
        } else if let spot = bestJumpSpot(from: pos, exclude: anchor.loopID) {
            startJump(to: spot.point)
        } else {
            turnTo(chance(0.5) ? 1 : -1, then: .walk, for: randRange(1.5, 3))
        }
    }

    private func beginBuilding() {
        guard var h = hammock else { return }
        h.rect = hammockRect(left: h.left)
        if h.progress <= 0.02 {
            h.style = HammockStyle.allCases.randomElement() ?? .sling
            h.seed = Int.random(in: 1...9999)
            h.load = 0
            h.progress = 0.02
        }
        hammock = h
        detachWeb(fade: true)
        queued = nil
        // Resume where it left off: the strand count is what the drawing
        // shows. All the long strands laid: straight to the tying-off.
        let n = Spider.buildCrossings
        if h.progress >= 0.88 {
            build = nil
            beginTieOff()
            return
        }
        buildStrand = h.progress < 0.36 ? 0 : 1 + Int((remap(h.progress, 0.36, 0.88, 0, CGFloat(n - 1))).rounded(.down))
        buildStrand = min(buildStrand, n - 1)
        // Odd strands run ceiling-to-wall, even ones wall-to-ceiling; it
        // starts each from the end it is nearer.
        let atWall = pos.distance(to: h.wallAnchor) < pos.distance(to: h.ceilingAnchor)
        build = atWall ? .fastenWall : .fastenCeiling
        if !atWall, buildStrand == 0 { buildStrand = 1 }
        buildThreadFrom = nil
        decisionIn = 0.05
    }

    /// The building, step by step: called from `think` whenever it is idle
    /// with a hammock on the go. Every step is ordinary walking, jumping and
    /// a fastening pose on the real surfaces round the corner.
    private func pursueBuild() {
        guard let step = build, var h = hammock, mode == .attached, let loop = map.loop(anchor.loopID) else {
            abandonBuild()
            return
        }
        let n = Spider.buildCrossings
        let sc = config.scale
        // Where it stands to reach each anchor with its spinnerets.
        let wallStand = hammockDoor(h)
        let ceilStand = V2(h.ceilingAnchor.x, h.ceilingAnchor.y - map.standoff)
        let onWall = loop.kind == .screenBorder
        let onCeiling = loop.kind == .menuBar
        decisionIn = 0.15

        switch step {
        case .fastenWall:
            guard onWall, pos.distance(to: wallStand) < 26 * sc else {
                walkOrHop(to: wallStand, wantWall: true)
                return
            }
            if activity != .fasten, !justFastened {
                // Tail toward the wall anchor.
                faceAlongEdge(awayFrom: h.wallAnchor)
                beginActivity(.fasten, dur: randRange(0.9, 1.3))
                justFastened = true
                return
            }
            justFastened = false
            // Stuck down: silk starts here, or this strand is done.
            if buildStrand > 0 { h.progress = strandProgress(buildStrand, of: n) }
            else { h.progress = max(h.progress, 0.10) }
            h.startDraping()
            hammock = h
            buildThreadFrom = h.wallAnchor
            if buildStrand >= n - 1 { finishStrands(); return }
            if buildStrand > 0 { buildStrand += 1 }
            build = .toCeiling
        case .toCeiling:
            guard onCeiling, pos.distance(to: ceilStand) < 26 * sc else {
                walkOrHop(to: ceilStand, wantWall: false)
                return
            }
            build = .fastenCeiling
        case .fastenCeiling:
            guard onCeiling, pos.distance(to: ceilStand) < 26 * sc else {
                walkOrHop(to: ceilStand, wantWall: false)
                return
            }
            if activity != .fasten, !justFastened {
                faceAlongEdge(awayFrom: h.ceilingAnchor)
                beginActivity(.fasten, dur: randRange(0.9, 1.3))
                justFastened = true
                return
            }
            justFastened = false
            if buildStrand == 0 { buildStrand = 1; h.progress = strandProgress(0, of: n) }
            else { h.progress = strandProgress(buildStrand, of: n); buildStrand += 1 }
            h.startDraping()
            hammock = h
            buildThreadFrom = h.ceilingAnchor
            if buildStrand >= n { finishStrands(); return }
            build = .toWall
        case .toWall:
            guard onWall, pos.distance(to: wallStand) < 26 * sc else {
                walkOrHop(to: wallStand, wantWall: true)
                return
            }
            build = .fastenWall
        }
    }

    /// How many times it crosses the corner laying silk. Each crossing
    /// lays a bundle of strands (silk comes out as several fibres), so the
    /// drawing fills in a few strands per fastening whatever the style.
    static let buildCrossings = 5

    /// Progress once crossing `k` (0-based) has been stuck down at both ends.
    private func strandProgress(_ k: Int, of n: Int) -> CGFloat {
        k == 0 ? 0.36 : 0.36 + 0.52 * CGFloat(k) / CGFloat(max(n - 1, 1)) + 0.001
    }

    private var justFastened = false
    /// Mending a torn hammock (see `beginMend`): how torn it was, and
    /// whether it lies down in it after.
    private var mending: (from: CGFloat, thenSleep: Bool)?
    /// On the silk: the legs step along the sling as on a ledge.
    private var nestWalking = false
    private var wokeUpInNest = false
    private var nestPrevPos = V2.zero
    /// Walking in or out along the sling: from where to where (sling u).
    private var nestWalkU: (from: CGFloat, to: CGFloat, dur: CGFloat) = (0, 0, 1)
    /// Which end of the sling it steps onto for the tying-off.
    private var nestFromWall = true

    /// Turns so that its abdomen — the spinnerets — is toward `point` along
    /// the edge it stands on.
    private func faceAlongEdge(awayFrom point: V2) {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        let seg = loop.segs[anchor.segIdx]
        let toward = (point - pos).dot(seg.dir)
        let dir: CGFloat = toward >= 0 ? -1 : 1
        if dir != walkDir {
            pendingDir = dir
            turnStyle = .shuffle
            beginActivity(.turn, dur: 0.8)
            queue(.fasten, randRange(0.9, 1.3))
        }
    }

    /// Gets it round the corner: along the wall, a hop across to the
    /// ceiling (the walls stop short of the menu bar), and along that.
    private func walkOrHop(to target: V2, wantWall: Bool) {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count, let h = hammock else { return }
        let sc = config.scale
        let onWall = loop.kind == .screenBorder
        let onCeiling = loop.kind == .menuBar
        func walkTo(_ p: V2) {
            walkToward(p)
            // Busy: a brisk, even pace, and the walk ends where it is going.
            bout = 1.2
            activityDur = min(activityDur, max(pos.distance(to: p) / max(config.walkSpeed * 1.1, 1), 0.3))
        }
        if (wantWall && onWall) || (!wantWall && onCeiling) { walkTo(target); return }
        guard onWall || onCeiling else { abandonBuild(); return }
        let corner = V2(h.left ? h.rect.minX : h.rect.maxX, h.rect.maxY)
        // The nearest standing spot on the other surface to the corner.
        let otherKind: SurfaceKind = wantWall ? .screenBorder : .menuBar
        var best: (d: CGFloat, p: V2)?
        for spot in map.sampleSpots(spacing: 30) where spot.loop.kind == otherKind {
            let d = spot.point.distance(to: corner)
            if best == nil || d < best!.d { best = (d, spot.point) }
        }
        guard let land = best else { abandonBuild(); return }
        // Near enough the corner: gather and hop across. Otherwise walk to
        // this surface's corner end first.
        if pos.distance(to: land.p) < 150 * sc, ballistic(from: pos, to: land.p) != nil {
            hurrying = true
            startJump(to: land.p)
            return
        }
        let seg = loop.segs[anchor.segIdx]
        let myEnd: V2 = onWall
            ? V2(pos.x, max(seg.a.y, seg.b.y) - 4)
            : (abs(seg.a.x - corner.x) < abs(seg.b.x - corner.x) ? seg.a : seg.b)
        walkTo(myEnd)
    }

    private func wallStandX(_ h: Hammock) -> CGFloat {
        h.left ? h.rect.minX + map.standoff : h.rect.maxX - map.standoff
    }

    /// All the long strands are down: onto the sling to tie it off.
    private func finishStrands() {
        guard var h = hammock else { return }
        h.progress = max(h.progress, 0.88)
        h.startDraping()
        hammock = h
        build = nil
        buildThreadFrom = nil
        beginTieOff()
    }

    /// Walks in along the sling from whichever end it is at, turns about in
    /// the middle tying the cross-ties off, and tests it with a bounce.
    private func beginTieOff() {
        guard let h = hammock else { return }
        nestFromWall = pos.distance(to: h.wallAnchor) < pos.distance(to: h.ceilingAnchor)
        mode = .nesting
        nestPhase = .building
        nestTime = 0
        nestDur = randRange(4.5, 6.0)
        legMode = .free
        anchorValid = false
        detachWeb(fade: true)
        queued = nil
        activity = .idle
        wag.velocity = 3
        mending = nil
    }

    /// Mending a torn hammock is the tying-off again: in along the sling
    /// and back and forth over the tear, laying fresh silk over it, a
    /// little longer the worse it is torn.
    private func beginMend(thenSleep: Bool) {
        guard let h = hammock, h.progress >= 1 else { return }
        beginTieOff()
        nestDur = randRange(3.5, 4.5) + 4 * h.damage
        mending = (from: h.damage, thenSleep: thenSleep)
    }

    /// Something got in the way (it fell, a window came over the corner, it
    /// was picked up): the job stops where it is. What is spun stays; it
    /// comes back to finish it another time.
    private func abandonBuild() {
        guard build != nil else { return }
        build = nil
        buildThreadFrom = nil
        justFastened = false
        hurrying = false
        if let h = hammock, h.progress < 0.36 { hammock = nil }
    }

    private func enterNest() {
        guard let h = hammock else { return }
        hammock!.load = 0
        mode = .nesting
        nestPhase = .entering
        nestTime = 0
        // In along the silk from wherever it steps on — the wall end,
        // usually — to the bed, on foot.
        let u0 = h.nearestU(to: pos)
        nestWalkU = (u0, h.bedU, max(0.4, abs(h.bedU - u0) * 2.4))
        nestDur = nestWalkU.dur
        nestZzzIn = 1.5
        nestPrevPos = pos
        legMode = .planted
        anchorValid = false
        detachWeb(fade: true)
        queued = nil
        activity = .idle
    }

    /// One frame of walking along the sling, `from` to `to` over `dur`:
    /// the body follows the curve and the legs step on it. Returns true
    /// when it has arrived.
    private func walkSling(_ h: Hammock, dt: CGFloat) -> Bool {
        let k = easeInOutSine(clamp(nestTime / max(nestWalkU.dur, 0.01), 0, 1))
        let uu = lerp(nestWalkU.from, nestWalkU.to, k)
        let ride = V2(0, 10 * config.scale)
        let target = h.point(at: uu) + ride
        hammock?.loadU = uu
        let forward: CGFloat = nestWalkU.to >= nestWalkU.from ? 1 : -1
        let along = h.tangent(at: uu) * forward
        pos = approach(pos, target, 10, maxSpeed: 170 * config.scale, dt)
        facing = along.x >= 0 ? 1 : -1
        headingTarget = along.angle + (facing < 0 ? .pi : 0)
        stepOnSilk(dt: dt)
        return nestTime >= nestWalkU.dur
    }

    /// Drives the gait from the distance the body actually covers on the
    /// silk, so the feet step and hold as they do on a ledge.
    private func stepOnSilk(dt: CGFloat) {
        nestWalking = true
        legMode = .planted
        surfaceNormal = V2(0, 1)
        travelLocal = V2(1, 0)
        let moved = pos.distance(to: nestPrevPos)
        nestPrevPos = pos
        speed = dt > 0 ? moved / dt : 0
        if boutStride < 10 { boutStride = 26 }
        gaitPhase += speed / (strideNow * config.scale) * dt
        if gaitPhase > 1 { gaitPhase -= gaitPhase.rounded(.down) }
    }

    private func updateNesting(dt: CGFloat) {
        guard var h = hammock else { leaveNest(startled: true); return }
        // A window over the corner: out of the hammock and away.
        if !map.isVisible(pos, depth: Int.max) {
            occludedFor += dt
            if occludedFor > 0.05 { occludedFor = 0; leaveNest(startled: true); return }
        } else {
            occludedFor = 0
        }
        nestTime += dt
        wagPhase += dt * 4
        // A film starting mid-build: the corner is over the picture now.
        if inCinema, nestPhase == .building {
            if mending == nil { hammock = nil }
            leaveNest(startled: false)
            return
        }
        switch nestPhase {
        case .building:
            // The long strands are all down (spun on the walls, see
            // `pursueBuild`); now it is on the silk itself: in along the
            // sling from the end it is at, turning about in the middle
            // tying the cross-ties off, and a test bounce at the end.
            let u = clamp(nestTime / nestDur, 0, 1)
            let sc = config.scale
            let ride = V2(0, 10 * sc)                       // it walks a little above the line
            var target: V2
            var along: V2
            var sway: CGFloat = 1.2
            let fromWall = nestFromWall
            if u < 0.35 {
                // Walking in along the sling to the bed.
                let k = easeInOutSine(u / 0.35)
                let uu = fromWall ? lerp(0.02, h.bedU, k) : lerp(0.98, h.bedU, k)
                target = h.point(at: uu) + ride
                along = h.tangent(at: uu) * (fromWall ? 1 : -1)
                sway = 1.4
            } else {
                // Tying off in the middle: a few steps back and forth over
                // the bed, turning about, patting it down.
                let k = (u - 0.35) / 0.65
                let uu = h.bedU + sin(k * .pi * 2) * 0.09
                target = h.point(at: uu) + ride
                along = h.tangent(at: uu) * (cos(k * .pi * 2) >= 0 ? 1 : -1)
                if k > 0.85, h.load < 0.01 { h.load = 0.6; bungee.velocity = 220 }   // a test bounce
            }
            h.progress = max(h.progress, 0.88 + 0.12 * u)
            // Mending: the tear closes as it goes back and forth over it.
            if let m = mending, u > 0.35 {
                h.damage = min(h.damage, m.from * (1 - easeInOutSine((u - 0.35) / 0.65)))
            }
            hammock = h
            pos = approach(pos, target, 8, maxSpeed: 150 * sc, dt)
            facing = along.x >= 0 ? 1 : -1
            headingTarget = along.angle + (facing < 0 ? .pi : 0)
            stepOnSilk(dt: dt)
            wag.step(to: sway, dt: dt)
            lift.step(to: 0, dt: dt)
            pitch.step(to: -0.08, dt: dt)
            crouch.step(to: 0.1, dt: dt)
            lid.step(to: 0, dt: dt)
            sleepiness.step(to: 0, dt: dt)
            nestDab = 0
            if u >= 1 {
                h.progress = 1
                if mending != nil { h.damage = 0 }
                hammock = h
                happy.velocity = 6
                setEmote(.sparkle, 1.0)
                let sleepAfter = mending?.thenSleep ?? wantsSleepAfterBuild
                mending = nil
                if sleepAfter {
                    enterNest()
                } else {
                    leaveNest(startled: false)
                }
            }
        case .entering:
            // In along the silk to the bed, on foot; then it settles.
            h.load = approach(h.load, 0.3, 1.4, dt)
            hammock = h
            wag.step(to: 1.0, dt: dt)
            crouch.step(to: 0.1, dt: dt)
            lift.step(to: 0, dt: dt)
            pitch.step(to: -0.06, dt: dt)
            lid.step(to: 0, dt: dt)
            if walkSling(h, dt: dt) {
                nestPhase = .sleeping
                nestTime = 0
                nestDur = randRange(20, 50) * (0.6 + personality.laziness)
                nestWalking = false
                legMode = .free
                facing = h.left ? 1 : -1
                // Settling into the bed sets the whole thing swinging.
                hammock?.loadU = nil
                nudgeHammock(randRange(18, 28))
                shiftIn = randRange(6, 14)
            }
        case .leaving:
            // Out along the silk to the wall end, and onto the wall.
            h.load = approach(h.load, 0.3, 2, dt)
            hammock = h
            wag.step(to: 0.8, dt: dt)
            crouch.step(to: 0.1, dt: dt)
            lift.step(to: 0, dt: dt)
            pitch.step(to: -0.06, dt: dt)
            if walkSling(h, dt: dt) { stepOffNest() }
        case .sleeping:
            // Curled up in it: it sinks in as it settles (the sling gives
            // under it), lies along the sag, tucks its legs in tight and
            // its head down, and breathes.
            h.load = approach(h.load, 1, 1.4, dt)
            hammock = h
            nestWalking = false
            legMode = .free
            let bed = nestCentre(h)
            pos = approach(pos, bed + V2(0, bodyWobble.value(t * 0.4) * 1.2), 4, dt)
            let along = h.tangent(at: h.bedU)
            facing = h.left ? 1 : -1
            headingTarget = (facing > 0 ? along : -along).angle + (facing < 0 ? .pi : 0) - 0.12 + sin(t * 0.7) * 0.02
            sleepiness.step(to: 1, dt: dt)
            lid.step(to: 1, dt: dt)
            crouch.step(to: 0.5, dt: dt)
            lift.step(to: -2 * config.scale, dt: dt)
            pitch.step(to: -0.14, dt: dt)
            wag.step(to: 0, dt: dt)
            nestDab = 0
            nestZzzIn -= dt
            if nestZzzIn <= 0 {
                nestZzzIn = randRange(3, 5)
                setEmote(.zzz, 2.8)
            }
            // Now and then it shifts in its sleep, and the sling rocks.
            shiftIn -= dt
            if shiftIn <= 0 {
                shiftIn = randRange(7, 18)
                nudgeHammock(randRange(8, 16))
            }
            // A fast pointer right by it wakes it.
            if !fullScreenApp, !dormant, cursor.distance(to: pos) < 70 * config.scale && cursorVel.length > 500 {
                leaveNest(startled: true)
                return
            }
            if nestTime > nestDur && (!fullScreenApp || greetOnWaking) { leaveNest(startled: false) }
        }
    }

    // MARK: Hammock swing

    /// The sling as a slow pendulum. A puff of breeze sets it rocking now
    /// and then; with the spider in it the rocking comes more often — its
    /// weight shifting — and dies away more slowly.
    private func rockHammock(dt: CGFloat) {
        guard var h = hammock, h.progress > 0.3 else { hammockSwayVel = 0; return }
        let occupied = mode == .nesting
        breezeIn -= dt
        if breezeIn <= 0 {
            breezeIn = occupied ? randRange(3, 9) : randRange(9, 26)
            nudgeHammock(randRange(5, 16))
        }
        let omega: CGFloat = 2.8                       // about a 2 s swing
        let damping: CGFloat = occupied ? 0.3 : 0.5
        hammockSwayVel += (-omega * omega * h.sway - 2 * damping * hammockSwayVel) * dt
        h.sway += hammockSwayVel * dt
        if abs(h.sway) < 0.03, abs(hammockSwayVel) < 0.1 { h.sway = 0; hammockSwayVel = 0 }
        if h.sway != hammock!.sway { hammock = h }
    }

    /// Gives the sling a push of `strength` px/s, either way.
    private func nudgeHammock(_ strength: CGFloat) {
        hammockSwayVel += strength * (chance(0.5) ? 1 : -1)
    }

    /// Out of the sac: onto the wall beside it, or a startled tumble.
    private func leaveNest(startled fright: Bool) {
        mending = nil
        sleepiness.value = 0
        lid.value = 0
        wokeUp = false
        if !fright, mode == .nesting, let h = hammock, h.progress >= 1,
           nestPhase == .sleeping || nestPhase == .entering || nestPhase == .building {
            // Up, and out along the silk to the wall end on foot first.
            wokeUpInNest = nestPhase == .sleeping
            nestPhase = .leaving
            nestTime = 0
            let u0 = h.nearestU(to: pos)
            nestWalkU = (u0, 0.02, max(0.5, abs(u0 - 0.02) * 2.4))
            nestPrevPos = pos
            legMode = .planted
            return
        }
        hammock?.load = 0
        if fright {
            mode = .airborne
            air = .fall
            vel = V2(hammock.map { $0.left ? 90 : -90 } ?? 0, -40)
            airTime = 0
            noAttachFor = 0.1
            launchLoop = ""
            legMode = .free
            startled.velocity = 12
            setEmote(.surprise, 0.7)
            return
        }
        stepOffNest()
    }

    /// From the wall end of the sling onto the wall itself.
    private func stepOffNest() {
        nestWalking = false
        hammock?.load = 0
        if let h = hammock, let spot = map.nearestSpot(to: hammockDoor(h), within: 60) {
            // The landing glides it the last little way onto the ledge.
            vel = .zero
            land(on: spot.anchor, seg: spot.seg)
            anchorGlide = 6
            if wokeUpInNest {
                beginActivity(.stretch, dur: 1.4)
                queue(.shake, 0.5)
            }
            wokeUpInNest = false
        } else {
            mode = .airborne
            air = .fall
            vel = .zero
            airTime = 0
            noAttachFor = 0.05
            legMode = .free
        }
    }

    // MARK: Hammock API

    /// Up and out of its hammock, if it is in it: along the silk to the
    /// wall and off (somewhere else wants it — the habitat, say).
    func leaveHammock() {
        guard mode == .nesting else { return }
        wake()
        leaveNest(startled: false)
    }

    /// A hammock saved from last time.
    func restoreHammock(left: Bool, style: HammockStyle = .sling, seed: Int = 4242) {
        hammock = Hammock(left: left, rect: hammockRect(left: left), progress: 1, damage: 0, style: style, load: 0, seed: seed)
    }

    /// Re-fits the hammock to the screen after the displays change.
    func refitHammock() {
        guard var h = hammock else { return }
        h.rect = hammockRect(left: h.left)
        hammock = h
    }

    /// The pointer wiping across the sac tears it; enough wiping clears it.
    /// An unfinished one goes with a single wipe.
    func wipeHammock(at p: V2, movement: CGFloat) {
        guard var h = hammock, movement > 0.5,
              h.rect.insetBy(dx: -6, dy: -6).contains(p.point) || h.nearest(to: p).distance(to: p) < 14 else { return }
        h.damage = min(1, h.damage + movement / (h.progress >= 1 ? 520 : 60))
        hammock = h
        if h.damage >= 1 {
            clearHammock()
        } else if mode == .nesting, nestPhase == .sleeping, h.damage > 0.3 {
            // Rudely woken.
            leaveNest(startled: true)
        }
    }

    /// Menu commands.
    func buildHammock() {
        guard config.hammocks else { return }
        wake()
        if hammock == nil || hammock!.progress < 1 {
            hammock = nil
            goHome(.build)
        } else {
            goHome(.sleep)
        }
    }

    func napInHammock() {
        wake()
        guard let h = hammock, h.progress >= 1 else { buildHammock(); return }
        goHome(.sleep)
    }

    func clearHammock() {
        guard hammock != nil else { return }
        hammock = nil
        homing = nil
        if mode == .nesting { leaveNest(startled: true) }
    }

    var hasHammock: Bool { hammock.map { $0.progress >= 1 } ?? false }
    /// Any silk in the corner at all, finished or not.
    var hasAnyHammock: Bool { hammock != nil }

    /// An unfinished hammock nobody is working on is abandoned: the few
    /// threads fade away rather than hanging about half-made for ever.
    private func tidyAbandonedHammock() {
        guard let h = hammock, h.progress < 1 else { return }
        let building = (mode == .nesting && nestPhase == .building) || build != nil
        // A part-spun hammock with a few strands down is kept: it comes
        // back to finish it. Less than that is nothing to keep.
        if !building && homing != .build && h.progress < 0.36 { hammock = nil }
    }

    // MARK: Held

    private func updateHeld(dt: CGFloat) {
        // The grab point tracks the pointer almost rigidly — a soft spring here
        // reads as lag, not weight. The weight comes from the body swinging
        // against the motion and the legs flailing.
        let target = cursor + grabOffset
        let prev = pos
        pos = approach(pos, target, 90, dt)

        if webActive {
            let r = pos - webAnchor
            let d = r.length
            if d > webLen {
                pos = webAnchor + r.normalized * (webLen + (d - webLen) * 0.55)
            }
        }
        if dt > 0 { vel = (pos - prev) / dt }

        if abs(vel.x) > 120 { facing = vel.x >= 0 ? 1 : -1 }
        headingTarget = clamp(-vel.x * 0.0009, -0.6, 0.6) + sin(t * 5) * 0.03

        legMode = .free
        happy.value = max(happy.value, pettingScore > 0.85 ? 0.9 : 0)
        stretch.step(to: 1.05, dt: dt)
        crouch.step(to: 0, dt: dt)
        lift.step(to: 0, dt: dt)
        pitch.step(to: 0, dt: dt)
        wag.step(to: 0, dt: dt)
        lid.step(to: 0, dt: dt)
    }

    // MARK: - Look / blink / emote

    /// The look direction is in *screen* space. Watching the pointer when it
    /// is about, glancing where it is going when walking, and otherwise
    /// darting about the way an idle animal's eyes do.
    private func updateLook(dt: CGFloat) {
        var target = V2.zero
        var idle = false
        let dCursor = cursor.distance(to: pos)
        let watching = (config.followCursor && dCursor < 460 && t - lastUserActivity < 12)
            || isHeld || pettingScore > 0.4 || activity == .curious || activity == .greet || activity == .stare
        if let dot = laser {
            target = (dot - pos).normalized
        } else if noticing {
            target = (commotionAt - pos).normalized
        } else if activity == .peekaboo, mode == .attached, config.followCursor {
            target = (cursor - pos).normalized * ((peek?.stage ?? 0) >= 3 ? 1 : 0.6)
        } else if activity == .watch, mode == .attached {
            // Eyes on the picture: up at the middle of the screen, with the
            // odd drift as things happen on it.
            let f = map.screenFrame(containing: pos)
            let centre = V2(f.midX + idleLook.x * 300, f.midY + idleLook.y * 120)
            idleLookIn -= dt
            if idleLookIn <= 0 {
                idleLookIn = randRange(1.5, 4.0)
                idleLook = V2(randRange(-1, 1), randRange(-1, 1))
            }
            target = (centre - pos).normalized * 0.75
        } else if huntTarget != nil || caught != nil, let q = caught ?? prey.first(where: { $0.id == huntTarget }) {
            target = (q.pos - pos).normalized * (caught != nil ? 0.5 : 1)
        } else if let id = toyPlay?.id, let toy = toy(id) {
            target = (toy.pos - pos).normalized
        } else if let e = eyeOn, t < eyeOnUntil, mode == .attached {
            // Something in the tank it is looking at.
            target = (e - pos).normalized
        } else if mode == .clinging || cursorHunt != .none || interest > 0.05 {
            // Eyes locked on the pointer.
            target = (cursor - pos).normalized
        } else if watching {
            target = (cursor - pos).normalized
        } else if t < skyLookUntil {
            // Up at the sky: a rainbow, the northern lights, the snow coming
            // down on it.
            target = V2(idleLook.x * 0.35, 0.9)
        } else if eyesOnYou {
            // Turned round to look at you: straight at you.
            target = .zero
        } else if speed > 2 {
            let ahead = V2.angle(heading) * facing * 0.6
            // Walking turned round to you, its eyes are on you as it goes;
            // poking along nose down, on the ledge just in front of it.
            if worn.eyes > 0 {
                target = ahead * (1 - worn.eyes)
            } else {
                let down = (V2.angle(heading) * facing * 0.5 - surfaceNormal * 0.7).normalized * 0.75
                target = V2.lerp(ahead, down, -worn.eyes)
            }
        } else if activity == .peek {
            target = (V2.angle(heading) * facing + V2(0, -1)).normalized * 0.8
        } else {
            idleLookIn -= dt
            if idleLookIn <= 0 {
                idleLookIn = randRange(0.6, 2.6)
                idleLook = chance(0.3) ? .zero : V2.angle(randRange(-.pi, .pi)) * randRange(0.3, 0.8)
            }
            target = idleLook
            idle = true
        }
        idleEyes = idle
        lookSpring.step(to: target.clampedLength(1), dt: dt)
    }

    private func updateBlink(dt: CGFloat) {
        if blinkT >= 0 {
            blinkT += dt
            if blinkT > 0.19 {
                if blinkTwice {
                    blinkTwice = false
                    blinkT = -1
                    blinkIn = 0.12
                } else {
                    blinkT = -1
                    blinkIn = randRange(1.6, 6.0)
                }
            }
        } else {
            blinkIn -= dt
            if blinkIn <= 0 {
                blinkT = 0
                if blinkIn > -0.5 && chance(0.25) { blinkTwice = true }
            }
        }
    }

    private var blinkValue: CGFloat {
        guard blinkT >= 0 else { return 0 }
        return sin(blinkT / 0.19 * .pi)
    }

    private func setEmote(_ e: Emote, _ dur: CGFloat) {
        // A thought it is in the middle of is not wiped by a passing note or
        // sparkle; only a start (or another thought) replaces it.
        if emote == .thought, emoteTime < emoteDur, e != .thought, e != .surprise, e != .exclaim, e != .none { return }
        emote = e
        emoteTime = 0
        emoteClock = 0
        emoteDur = dur
    }

    private func updateEmote(dt: CGFloat) {
        guard emote != .none else { return }
        emoteTime += dt
        emoteClock += dt
        if emote == .zzz && activity == .sleep { emoteTime = min(emoteTime, emoteDur * 0.5) }
        if emoteTime > emoteDur { emote = .none }
    }

    // MARK: - Legs

    private func poseTarget(_ i: Int) -> V2 {
        let leg = legs[i]
        let rest = leg.rest
        let near = i < 4
        let k = i % 4
        let reach = rest - leg.hip
        let u = activityDur > 0 ? clamp(activityTime / activityDur, 0, 1) : 0

        switch (mode, activity) {
        case (.held, _):
            let curl = leg.hip + reach * 0.45
            let kick = V2(sin(t * 9 + CGFloat(i) * 1.1), cos(t * 7.5 + CGFloat(i) * 0.9)) * 3.2
            return curl + kick
        case (.clinging, _):
            // Hanging off the pointer, head up: the front two pairs hooked
            // round the hotspot past the mouth, the rest tucked in and
            // kicking — harder the more it is being shaken.
            let grip = toLocal(cursor)
            let struggle = 1 + clamp(clingShake, 0, 2) * 1.5
            let kick = V2(sin(t * 8 * struggle + CGFloat(i) * 1.1), cos(t * 6.5 * struggle + CGFloat(i) * 0.9)) * 2.2 * struggle
            let side: CGFloat = near ? 1 : -1
            switch k {
            case 0: return grip + V2(3, side * 4.5) + kick * 0.25
            case 1: return grip + V2(-3, side * 7) + kick * 0.35
            case 2: return leg.hip + reach * 0.5 + kick * 0.6
            default: return leg.hip + reach * 0.6 + V2(-2, -2) + kick
            }
        case (.attached, .shoot):
            // One front leg thrown out along the line, the rest braced.
            if k == 0 && near {
                let aim = toLocal(shotTarget).normalized * 30
                return V2(max(aim.x, 10), max(aim.y, 6))
            }
            return rest + V2(k < 2 ? 2 : -2, 0)
        case (.nesting, _):
            if nestPhase == .sleeping {
                // Curled up: every leg drawn in tight under the body, the
                // front pair folded over the face, breathing gently.
                let breathe = leg.wobble.value(t * 0.5) * 0.5
                let tuck = leg.hip + reach * 0.28 + V2(k < 2 ? 3 : -3, 2.5 + CGFloat(k % 2))
                if k == 0 { return V2(leg.hip.x + 9, leg.hip.y - 5 + (near ? 0 : 1.5)) + V2(0, breathe) }
                return tuck + V2(0, breathe)
            }
            // Spinning: the front legs reach out and pat the silk in turn;
            // the hind pair combs the thread out from the spinnerets in
            // long alternating strokes; a dab at an anchor draws them in.
            let ph = t * 6 + CGFloat(k) * 1.5 + (near ? 0 : .pi)
            if k == 3 {
                let stroke = sin(t * 5 + (near ? 0 : .pi))
                return V2(leg.hip.x - 10 + stroke * 6, -6 - abs(stroke) * 4 + (near ? 0 : 1)) * (1 - nestDab * 0.4) + rest * (nestDab * 0.4)
            }
            let out: CGFloat = k == 0 ? 8 : 0
            return rest + V2(out + sin(ph) * 3, 4 + cos(ph) * 3.5)
        case (.airborne, _):
            if air == .jump && airTime < 0.16 {
                // The push-off: everything driven back and down behind it.
                return leg.hip + V2(-reach.x * 0.4 - 10, reach.y * 1.1)
            }
            if airShot != nil {
                // Gathered in for the twist and the shot, the hind pair
                // drawn up by the spinnerets to guide the line out.
                let tuck = leg.hip + reach * 0.55 + V2(k < 2 ? 2 : -3, 3)
                if k == 3 { return V2(leg.hip.x - 8, -4 + (near ? 0 : 1.5)) }
                return tuck
            }
            let stretchOut: CGFloat = air == .jump ? 1.15 : 1.05
            var target = leg.hip + reach * stretchOut + V2(0, 6)
            target.x += k < 2 ? 5 : -5
            let flutter = V2(leg.wobble.value(t * 3.2) * 1.6, leg.wobble.value(t * 2.6 + 2) * 2.0)
            let flight = target + flutter
            if landingReach > 0.001 {
                // Reaching for the surface it is about to land on: the feet
                // go out to where they will stand, a little past it.
                let r = SpiderRenderer.rig(i, profile: SpiderRenderer.profileAmount(yaw: yaw), look: look)
                let stand = r.foot + V2(k < 2 ? 3 : -3, -3)
                return V2.lerp(flight, stand, smoothstep(landingReach))
            }
            return flight
        case (.attached, .sleep):
            return sleepFoot(i, leg.hip + reach * 0.72 + V2(0, leg.wobble.value(t * 0.5) * 0.6))
        case (.attached, .groom):
            if k == 0 && near {
                let a = t * 7
                return V2(20 + sin(a) * 3.0, 2 + cos(a) * 3.5)
            }
            return rest + V2(leg.wobble.value(t) * 0.5, 0)
        case (.attached, .wave):
            if k == 0 && near {
                // Big sweeps from the shoulder, three of them.
                let a = sin(u * .pi * 6) * 0.65
                return V2(16 + cos(a + 0.4) * 9, 14 + sin(a + 0.4) * 11)
            }
            if k == 0 && !near { return V2(leg.hip.x + 12, 2) }   // other front leg up a little
            return rest
        case (.attached, .eat):
            // Front pair holds the meal up to the mouth, turning it over;
            // the second pair braces.
            if k == 0 {
                let a = t * 5 + (near ? 0 : .pi)
                return V2(19 + sin(a) * 1.4, -8 + cos(a) * 1.6 + (near ? 0 : 1))
            }
            if k == 1 { return rest + V2(3, 0) }
            return rest
        case (.attached, .curious):
            // Two legs come up and feel the air (see `raisedSide`).
            if let side = raisedSide(i) {
                let a = t * 4 + (side > 0 && near ? 0 : 1.2)
                if liftsOuterPair { return faceOnRaise(i, side: side, out: 26 + sin(a) * 2.5, up: 16 + cos(a) * 3) }
                return V2(side * (26 + sin(a) * 2.5), 6 + cos(a) * 3)
            }
            if liftsOuterPair, let out = faceOnOuter(i) { return out }
            return standingFoot(i, braced: false)
        case (.attached, .feel):
            // The front legs out to what is in front of it (`feelAt`), and a
            // light tap or two on it with each in turn; the rest stand.
            let feeler = liftsOuterPair ? raisedSide(i) != nil : k == 0
            if feeler, let w = feelAt {
                let rig = SpiderRenderer.rig(i)
                let reach = ((rig.knee - rig.hip).length + (rig.foot - rig.knee).length) * 0.94
                var aim = toLocal(w)
                let v = aim - leg.hip
                if v.length > reach { aim = leg.hip + v.normalized * reach }
                // Off it and back down on it: the near leg and the far one in turn.
                let tap = max(0, sin(t * 5.5 + (near ? 0 : 2.3)))
                return aim + toLocalDir(feelNormal).normalized * (tap * 5)
            }
            if liftsOuterPair, let out = faceOnOuter(i) { return out }
            return standingFoot(i, braced: k == 1)
        case (.attached, .drink):
            // The front pair down at the water's edge either side of the
            // mouth, holding it there; the rest braced.
            if k == 0, let w = sipAt {
                let rig = SpiderRenderer.rig(i)
                let reach = ((rig.knee - rig.hip).length + (rig.foot - rig.knee).length) * 0.9
                var aim = toLocal(w) + V2(near ? -5 : -1, 3)
                let v = aim - leg.hip
                if v.length > reach { aim = leg.hip + v.normalized * reach }
                let down = smoothstep(clamp(activityTime / 0.6, 0, 1)) * smoothstep(clamp((activityDur - activityTime) / 0.45, 0, 1))
                return Spider.swing(rest, aim, about: leg.hip, down)
            }
            if liftsOuterPair, let out = faceOnOuter(i) { return out }
            return standingFoot(i, braced: k == 1)
        case (.attached, .fidget):
            // The near front foot taps twice.
            if k == 0 && near {
                let tap = abs(sin(u * .pi * 2))
                return rest + V2(3, tap * 7)
            }
            return rest
        case (.attached, .scratch):
            // The near back leg comes up and scratches the abdomen.
            if k == 3 && near {
                let jitter = sin(t * 26) * 2
                return V2(-16 + jitter, 6 + sin(t * 13) * 1.5)
            }
            return rest
        case (.attached, .peekaboo) where (peek?.stage ?? 0) >= 3:
            // Boo: two legs thrown up (see `raisedSide`), standing on the rest.
            if let side = raisedSide(i) {
                let a = t * 5 + (side > 0 && near ? 0 : 0.9)
                // Face on, up and out either side of the head, knees bent
                // outward, as in a greeting — not in across the face.
                if liftsOuterPair { return faceOnRaise(i, side: side, out: 21 + sin(a) * 2, up: 34 + cos(a * 1.3) * 2) }
                return V2(side * (15 + sin(a) * 3), 24 + cos(a * 1.3) * 2)
            }
            if liftsOuterPair, let out = faceOnOuter(i) { return out }
            return standingFoot(i, braced: k == 1)
        case (.attached, .hop):
            // On the ledge but for the flight, which places them itself (see
            // `updateLegControllers`).
            return rest
        case (.attached, .drum):
            // The front pair drum: a burst of quick alternating taps, then
            // a pause, then a few beats with both together — the foot lifts
            // and comes down a little ahead of where it stood.
            if k == 0 {
                let beat = drumBeat()
                let phase = drumPhase(near: near)
                let lift = max(0, sin(phase * .pi)) * (beat > 0.5 ? 10 : 0)
                let ahead: CGFloat = 7 + (near ? 0 : 3)
                return V2(rest.x + ahead + lift * 0.3, rest.y + lift)
            }
            if k == 1 { return rest + V2(2, 0) }
            return rest
        case (.attached, .greet):
            // Seen face on, the outermost pair are its front legs: both go
            // straight up beside the head and wave a little; the next pair
            // come up half way. Symmetric, so nothing jumps as it turns.
            // Each leg stays on the side of the face its foot stands on —
            // none sweeps across in front of it to get to the other side.
            // Its two front legs (see `raisedSide`) go up beside the head,
            // one either side, and wave a little; the other six stand.
            if i == 1 || i == 2 {
                let side: CGFloat = i == 1 ? 1 : -1
                let a = t * 4 + (side > 0 ? 0 : 0.8)
                let up = smoothstep(clamp(activityTime / 0.45, 0, 1))
                let raised = faceOnRaise(i, side: side, out: 21 + sin(a) * 2, up: 34 + cos(a * 1.3) * 2)
                return Spider.swing(rest, raised, about: leg.hip, up)
            }
            if let out = faceOnOuter(i) { return Spider.swing(rest, out, about: leg.hip, smoothstep(clamp(activityTime / 0.45, 0, 1))) }
            return standingFoot(i, braced: false)
        case (.attached, .armsUp):
            // Two legs straight up, swaying (see `raisedSide`). The rest
            // stay planted — the next pair braced a touch wider to take its
            // weight — so it always stands on six.
            if let side = raisedSide(i) {
                let a = t * 3.5 + (side > 0 && near ? 0 : 0.9)
                // Face on, up and out either side of the head, knees bent
                // outward, as in a greeting — not in across the face.
                if liftsOuterPair { return faceOnRaise(i, side: side, out: 21 + sin(a) * 2, up: 34 + cos(a * 1.3) * 2) }
                return V2(side * (14 + sin(a) * 3), 24 + cos(a * 1.3) * 2)
            }
            if liftsOuterPair, let out = faceOnOuter(i) { return out }
            return standingFoot(i, braced: k == 1)
        case (.attached, .roll):
            // Curled up tight: every leg folds at the knee, foot drawn in
            // close under the hip, so the ball is a bundle of bent legs
            // rather than a smooth lump, as a spider curled up is. The
            // knees fan out round the ball — the front pairs' forward and
            // under the face, the back pairs' back under the abdomen — and
            // each foot goes wherever puts its knee there.
            let rig = SpiderRenderer.rig(i, profile: 1, look: look)
            let kneeOff = (rig.knee - rig.hip).angle - (rig.foot - rig.hip).angle
            let kneeAng: CGFloat = (near ? [-0.2, -0.85, -2.3, -2.8] : [-0.5, -1.15, -2.0, -3.1])[k]
            let footAng = kneeAng - kneeOff
            let tuck = leg.hip + V2(cos(footAng), sin(footAng)) * (rig.foot - rig.hip).length * 0.45
            let r = rollPhase()
            switch r.phase {
            case 0:
                // The legs come in a pair at a time from the back, the
                // front pair last, folding under the face as it goes over.
                let start = 0.3 + CGFloat(3 - k) * 0.1
                return V2.lerp(rest, tuck, smoothstep(clamp((r.v - start) / 0.3, 0, 1)))
            case 1:
                // A ball of legs is never quite still: they clutch and
                // shift as it goes round.
                let jitter = V2(sin(t * 13 + CGFloat(i) * 1.7), cos(t * 10 + CGFloat(i) * 1.3)) * 0.5
                return tuck + jitter
            default:
                // Out they come to catch it, the front pair first, reaching
                // for the ledge.
                let start = CGFloat(k) * 0.07
                return V2.lerp(tuck, rest, smoothstep(clamp((r.v - start) / 0.4, 0, 1)))
            }
        case (.attached, .dance):
            // Front legs pump up and down in turn.
            if k == 0 {
                let a = t * 9 + (near ? 0 : .pi)
                return V2(20, 6 + sin(a) * 9)
            }
            return rest
        case (.attached, .legStretch):
            // Back legs take turns stretching out behind.
            if k == 3 {
                let first = u < 0.5
                let mine = (near && first) || (!near && !first)
                if mine {
                    let s = sin(((first ? u : u - 0.5) * 2) * .pi)
                    return V2(rest.x - 12 * s, rest.y + 6 * s)
                }
            }
            return rest
        case (.attached, .spin):
            return rest
        case (.attached, .stretch):
            // Everything out to full reach, front legs high.
            let s = sin(u * .pi)
            var target = leg.hip + reach * (1 + 0.18 * s)
            if k == 0 { target.y += 10 * s }
            return target
        case (.attached, .turn):
            // Feet shuffle round to where they stand in the blended layout.
            return SpiderRenderer.rig(i, profile: SpiderRenderer.profileAmount(yaw: yaw), look: look).foot
        default:
            let profile = SpiderRenderer.profileAmount(yaw: yaw)
            return profile > 0.98 ? rest : SpiderRenderer.rig(i, profile: profile, look: look).foot
        }
    }

    /// The path of a foot stepping from `from` to `to`, `u` of the way: a
    /// straight reach along the ledge, but a foot coming down from up high
    /// (after a wave, a greeting) folds in toward the body on the way so the
    /// leg bends at the knee instead of sweeping out straight like a bar.
    private func stepPath(_ i: Int, from: V2, to: V2, u: CGFloat) -> V2 {
        let high = max(0, from.y - max(to.y, legs[i].hip.y) - 6)
        guard high > 0 else { return V2.lerp(from, to, easeInOutSine(u)) }
        // Swung down about the hip, drawing in as it goes, with proper
        // two-bone bending — knee up and out — so the leg folds like an
        // elbow rather than sweeping down as one straight bar.
        let hip = legs[i].hip
        let a = from - hip, b = to - hip
        let e = easeInOutSine(u)
        let ang = a.angle + angleDelta(a.angle, b.angle) * e
        let len = lerp(a.length, b.length, e) * (1 - 0.4 * sin(u * .pi))
        let inward: CGFloat = hip.x >= 0 ? -1 : 1
        legBend[i] = V2(-inward * 0.6, 1).normalized
        return hip + V2.angle(ang) * len
    }

    /// Brings a foot that is off the ledge (up in the air from a wave, a
    /// greeting, a grip on a line) down onto `target` as one deliberate
    /// step; a foot already near the ledge just eases on. Returns true while
    /// it has hold of the foot.
    private func settleFoot(_ leg: inout Leg, _ i: Int, to target: V2, dt: CGFloat) -> Bool {
        // The step's ends are fixed in the world, not to the body: a body
        // still coming down onto a ledge, or leaning as it lands, does not
        // carry the foot with it past where the ledge is. (A step begun
        // this frame is already in this frame's terms.)
        if leg.settle >= 0 {
            leg.swingFrom = leg.swingFrom.rotated(by: -legDTheta) - legOverFeet
            leg.settleTo = leg.settleTo.rotated(by: -legDTheta) - legOverFeet
        }
        if leg.settle < 0 {
            let far = leg.foot.distance(to: target)
            let high = leg.foot.y > max(target.y, leg.hip.y) + 5
            // (Landing, any foot well off its spot steps there, none left
            // to slide into place after the body has stopped; one only a
            // little off closes up quickly instead of taking a step.)
            guard absorbingLanding ? far > 6 || high : far > 5 && (high || far > 14) else { return false }
            // A target nowhere near where this foot ever rests is the edge
            // snapper picking the wrong edge (a body still swinging down
            // onto a corner): not something to step to.
            guard target.distance(to: leg.rest) < 22 else { return false }
            leg.settle = 0
            leg.swingFrom = leg.foot
            leg.settleTo = target
        }
        let quick = t - landedAt < Spider.landHold
        // Landing, the body is still lurching and sinking under the step:
        // it aims at where its spot is now, so it lands there in one step
        // rather than landing short and having to take another.
        if absorbingLanding {
            leg.settleTo = target
        } else if mode == .attached, speed > 1, legController == .gait, footCornered(i) > 0,
                  let loop = map.loop(anchor.loopID), surfaceSide(toWorld(leg.settleTo), loop) > max(config.scale, 0.05) {
            // Likewise stepping on round a corner as it walks, once the spot
            // it set off for has gone round with the body — the step is held
            // to the body walking, not the ground — out into the air.
            leg.settleTo = target
        }
        leg.settle += dt / (quick ? landStep : 0.24)
        let u = clamp(leg.settle, 0, 1)
        leg.lift = sin(u * .pi) * (quick ? 0.3 : 0.7)
        leg.foot = stepPath(i, from: leg.swingFrom, to: leg.settleTo, u: u) + V2(0, leg.lift * 3.5)
        // A spot still out of the leg's reach — the body not yet down onto
        // the ledge out of a landing, the ground a long way round a corner
        // — is reached for, the leg out toward it, and stood on once the
        // body has brought it near; the leg is never drawn out past its
        // length to get there.
        let hip = SpiderRenderer.rig(i, profile: SpiderRenderer.profileAmount(yaw: yaw), look: look).hip
        let most = max(legLength(i) * Spider.reachShare, leg.swingFrom.distance(to: hip))
        if leg.settleTo.distance(to: hip) > most, leg.foot.distance(to: hip) > most {
            leg.foot = hip + (leg.foot - hip).normalized * most
        }
        if u >= 1 { leg.settle = -1; leg.lift = 0 }
        return true
    }

    /// Which of the leg controllers has the feet this frame.
    private enum LegController { case gait, posed, turn, hang }
    private var legController: LegController = .gait
    /// A hand-off between controllers: each foot eases from where it
    /// really was into where the new controller puts it, instead of being
    /// teleported there in a frame.
    private var handoffFrom: [V2] = []
    private var handoffT: CGFloat = 1
    /// Onto a line, the way each foot is going round its hip (see `roundHip`).
    private var handoffTurn: [CGFloat?] = []
    private var modeBeforeLegs: Mode = .attached
    private static let handoffTime: CGFloat = 0.26
    /// Tools only: the hand-offs and the jolt limits, off, to compare.
    static var debugRawLegs = false
    /// Tools only: tally how far the feet glide over the ground while none
    /// is lifted (see `tallyGlide`), by what it was doing.
    static var debugGlideTally = false
    static var debugGlide: [String: CGFloat] = [:]
    static var debugGlideRuns: [(px: CGFloat, frames: Int, what: String)] = []
    private var glideRun: CGFloat = 0
    private var glideFrames = 0
    private var glideLabel = ""

    private func updateLegs(dt: CGFloat) {
        let before = legs.map(\.foot)
        let was = legController
        updateLegControllers(dt: dt)
        defer { limitFootJolts(dt: dt) }
        let onSurface = mode == .attached || mode == .nesting
        if legController != was {
            // A step in flight belongs to the clock that started it; the
            // next controller begins its own.
            for i in legs.indices { legs[i].swinging = false; legs[i].swingShift = 0 }
            // Eased only from one way of standing to another, or onto a
            // line. Picked up, launched, falling, the feet go with the body
            // at once; landing, the landing has them (see `absorbingLanding`).
            let eased = (onSurface && modeBeforeLegs == mode && !absorbingLanding) || onLine
            if eased, !Spider.debugRawLegs {
                handoffFrom = before
                handoffT = 0
                handoffTurn = []
            } else {
                handoffT = 1
            }
        }
        modeBeforeLegs = mode
        // (Nor in a hop, which is all over before a hand-off would be: the
        // hop's own poses take the feet off the ledge and back onto it.)
        if mode == .held || (mode == .airborne && !onLine) || absorbingLanding || activity == .hop { handoffT = 1 }
        guard handoffT < 1, handoffFrom.count == legs.count else { return }
        handoffT = min(1, handoffT + dt / Spider.handoffTime)
        let e = smoothstep(handoffT)
        for i in legs.indices {
            // On a surface the start point stays on the ground while the
            // body moves; on a line it goes with the body, and the foot
            // swings round the hip to where the line has it — at arm's
            // length, not in through the hip, however the body spins.
            if onSurface { handoffFrom[i] = handoffFrom[i].rotated(by: -legDTheta) - legOverFeet }
            if onLine {
                if handoffTurn.count != legs.count { handoffTurn = Array(repeating: nil, count: legs.count) }
                legs[i].foot = Spider.roundHip(handoffFrom[i], legs[i].foot, hip: legs[i].hip, e, turn: &handoffTurn[i])
            } else {
                legs[i].foot = V2.lerp(handoffFrom[i], legs[i].foot, e)
            }
        }
    }

    /// Each foot's last screen position and velocity, for the limiter.
    private var footWorld: [V2] = []
    private var footWorldVel: [V2] = []
    private var footLimitPos: V2 = .zero
    /// px/s² at scale 1: well above a quick step (under ~20 000), well
    /// below a foot teleported by an edge flicker or a hand-off.
    private static let footJolt: CGFloat = 26_000

    /// The last word on the feet, on a surface: whatever the controllers
    /// decided, a foot cannot pick up speed faster than a leg can move it —
    /// a target that flickers between the two edges of a corner as the body
    /// swings onto it, a leg handed from one pose to the next, all come
    /// out as quick movements instead of jumps. Only speeding up is capped:
    /// a foot may always stop at once, so nothing overshoots and swings
    /// back. Off the ground (a leap, a throw, a line) the feet go with the
    /// body as they are.
    private func limitFootJolts(dt: CGFloat) {
        let world = legs.map { toWorld($0.foot) }
        if Spider.debugGlideTally { tallyGlide(world: world, dt: dt) }
        let onSurface = (mode == .attached || mode == .nesting) && activity != .roll
        let bodyJump = pos.distance(to: footLimitPos) > 30 * config.scale
        footLimitPos = pos
        guard onSurface, !bodyJump, !Spider.debugRawLegs, dt > 0, footWorld.count == legs.count, footWorldVel.count == legs.count else {
            footWorldVel = footWorld.count == world.count ? zip(world, footWorld).map { ($0 - $1) / max(dt, 0.001) }
                : Array(repeating: .zero, count: world.count)
            footWorld = world
            return
        }
        let cap = Spider.footJolt * config.scale * landingJolt
        let profile = SpiderRenderer.profileAmount(yaw: yaw)
        defer { limitReach(profile: profile) }
        for i in legs.indices {
            var w = world[i]
            let from = footWorld[i]
            if Spider.limitJolt(&w, last: &footWorld[i], vel: &footWorldVel[i], cap: cap, dt: dt) {
                // Held back on its way somewhere past its own hip — a foot
                // thrown to the far side of it by a landing, or round a
                // corner — it goes round the hip at arm's length, as a leg
                // swings, not straight through it, where the knee has
                // nowhere to go.
                let hip = toWorld(SpiderRenderer.rig(i, profile: profile, look: look).hip)
                let near = legLength(i) * 0.15 * config.scale
                if projectOnSegment(hip, from, world[i]).dist < near, from.distance(to: hip) > 1, world[i].distance(to: hip) > 1 {
                    let ra = from.distance(to: hip), rb = world[i].distance(to: hip)
                    let turn = abs(angleDelta((from - hip).angle, (world[i] - hip).angle))
                    let arc = max(turn * max(ra, rb, near) + abs(rb - ra), 0.001)
                    w = Spider.swing(from, world[i], about: hip, clamp(from.distance(to: w) / arc, 0, 1))
                    footWorldVel[i] = (w - from) / dt
                    footWorld[i] = w
                }
                legs[i].foot = toLocal(w)
            }
        }
    }

    /// The last word on how far a foot is from its hip, on a surface:
    /// however it got there — held in the world while the body moved on
    /// over a gap, eased toward a spot that is out of reach — no leg is
    /// ever drawn out much past its own length. (An ordinary stride, the
    /// short second leg reaching out at the front of it, stays well inside
    /// this.)
    private func limitReach(profile: CGFloat) {
        guard mode == .attached, activity != .roll else { return }
        for i in legs.indices {
            // (From the hip as it is drawn — the body leaning, or squashed
            // down onto its legs by a landing — which is where the leg is.)
            let hip = drawnHip(i, profile: profile)
            // (A long stride — at a run, and small, strides are long for
            // its size — takes the feet further out at its ends.)
            var most = legLength(legBones[i] ?? i) * Spider.reachLimit + max(strideNow - Spider.longStride, 0) * 0.5
            // (Walking the natural way, a leg is only ever as long as it is.)
            if naturalWalk, legController == .gait { most = legLength(i) * 0.995 }
            // (Walking the refined way likewise — and never folded so far
            // up that its two bones would not meet.)
            var least: CGFloat = 0
            if refinedWalk, legController == .gait {
                let r = SpiderRenderer.rig(i, profile: profile, look: look)
                let give = refGiveNow.count == legs.count ? refGiveNow[i] : 1
                most = Spider.refSpan((r.knee - r.hip).length * give, (r.foot - r.knee).length * give, Spider.refOpenMost)
                least = abs((r.knee - r.hip).length - (r.foot - r.knee).length) * 1.04 + 0.3
            }
            let d = legs[i].foot - hip
            if d.length < least, d.length > 0.001 {
                legs[i].foot = hip + d * (least / d.length)
                if footWorld.count == legs.count { footWorld[i] = toWorld(legs[i].foot) }
                continue
            }
            guard d.length > most else { continue }
            legs[i].foot = hip + d * (most / d.length)
            if footWorld.count == legs.count { footWorld[i] = toWorld(legs[i].foot) }
        }
    }
    private static let reachLimit: CGFloat = 1.25
    private static let longStride: CGFloat = 45

    /// Leg `i`'s hip where the leg is drawn from, in the feet's frame:
    /// turned with the body's lean and squashed with it (see `modelLeg`).
    private func drawnHip(_ i: Int, profile: CGFloat) -> V2 {
        var hip = SpiderRenderer.rig(i, profile: profile, look: look).hip
        let bp = bodyPitchNow
        if abs(bp) > 0.0005 {
            let pivot = SpiderRenderer.leanPivot
            hip = pivot + (hip - pivot).rotated(by: bp) + V2(-bp * 8, bp * 2)
        }
        let sq = bodySquash()
        let g = SpiderRenderer.ground
        return V2(hip.x * sq.stretch, g + (hip.y - g) * sq.fatten)
    }

    /// Tools only: the body going along the ground, every foot down, and
    /// the feet sliding over the ground with it — gliding, as if on ice.
    /// Each glide is tallied by what it was doing.
    private func tallyGlide(world: [V2], dt: CGFloat) {
        var slip: CGFloat = 0
        if mode == .attached, activity != .roll, dt > 0, footWorld.count == world.count,
           legs.allSatisfy({ $0.lift < 0.05 && !$0.swinging && $0.settle < 0 }) {
            let body = legOverFeet.length
            let down = legs.indices.filter { legs[$0].foot.distance(to: groundFoot(legs[$0].foot)) < 1.5 }
            if body / dt > 20, down.count >= 6 {
                let s = down.map { (world[$0] - footWorld[$0] - legSurfaceWorld).length }.reduce(0, +) / CGFloat(down.count) / config.scale
                if s > body * 0.5 { slip = s }
            }
        }
        if slip > 0 {
            Spider.debugGlide["\(activity) \(legController)", default: 0] += slip
            if glideRun == 0 { glideLabel = String(format: "%@ %@ %.2fs after landing, %.2fs in", "\(activity)", "\(legController)", t - landedAt, activityTime) }
            glideRun += slip
            glideFrames += 1
        } else if glideRun > 0 {
            Spider.debugGlideRuns.append((glideRun, glideFrames, glideLabel))
            glideRun = 0
            glideFrames = 0
        }
    }

    /// Moves `last` on to `w`, holding back any part of the step that would
    /// have it pick up speed faster than `cap` (px/s²). Returns true if `w`
    /// was held back.
    private static func limitJolt(_ w: inout V2, last: inout V2, vel: inout V2, cap: CGFloat, dt: CGFloat) -> Bool {
        let step = w - last
        let most = (vel.length + cap * dt) * dt
        let held = step.length > most
        if held { w = last + step.normalized * most }
        vel = (w - last) / dt
        last = w
        return held
    }

    private func updateLegControllers(dt: CGFloat) {
        let scale = max(config.scale, 0.05)
        for i in legBend.indices { legBend[i] = nil; legBones[i] = nil }
        // Sprite space is rotated by `heading` and mirrored by the sign of the
        // yaw, so undoing the body's motion means rotating back and then
        // un-mirroring.
        let m = mirrorSign
        let dTheta = angleDelta(legFrameHeading, heading) * m
        bodySpin = dt > 0 ? clamp(angleDelta(legFrameHeading, heading) / dt, -15, 15) : 0
        var deltaLocal = ((pos - legFramePos) / scale).rotated(by: -heading)
        deltaLocal.x *= m
        legFramePos = pos
        legFrameHeading = heading
        // The body's motion over its feet: its own, not the surface's.
        var overFeet = deltaLocal
        if mode == .attached {
            var surf = (surfaceMotion / scale).rotated(by: -heading)
            surf.x *= m
            overFeet = deltaLocal - surf
        }
        legSurfaceWorld = mode == .attached ? surfaceMotion : .zero
        surfaceMotion = .zero
        legOverFeet = overFeet
        legDTheta = dTheta

        let profile = SpiderRenderer.profileAmount(yaw: yaw)
        let duty = Spider.swingDuty

        // A turn on the spot: the feet step round to where they stand in the
        // blended layout, in the usual tetrapod waves, each planted foot
        // holding its place until its turn to move. Two full step cycles fit
        // in a turn, so every leg re-plants twice — once toward the front view
        // and once into the new profile.
        if mode == .attached && activity == .turn {
            legController = .turn
            turnGait += dt * (2.0 / max(activityDur, 0.3))
            for i in legs.indices {
                var leg = legs[i]
                leg.footVel = .zero
                let ph = (turnGait + leg.phase).truncatingRemainder(dividingBy: 1)
                let target = groundFoot(SpiderRenderer.rig(i, profile: profile, look: look).foot, spread: true, leg: i)
                if ph >= duty { leg.skipSwing = false }
                // A leg whose window was already half over when the turn
                // began waits for its next one, rather than appear mid-step.
                if ph < duty, !leg.swinging, ph > duty * 0.3 { leg.skipSwing = true }
                if ph < duty, !leg.skipSwing {
                    leg.settle = -1
                    if !leg.swinging {
                        leg.swinging = true
                        leg.swingFrom = leg.foot
                        leg.swingPh0 = ph
                    }
                    let u = clamp((ph - leg.swingPh0) / max(duty - leg.swingPh0, 0.01), 0, 1)
                    let base = stepPath(i, from: leg.swingFrom, to: target, u: u)
                    leg.lift = sin(u * .pi)
                    leg.foot = base + V2(0, leg.lift * 4.0)
                } else {
                    leg.swinging = false
                    leg.lift = approach(leg.lift, 0, 16, dt)
                    // A foot still in the air from whatever came before
                    // steps down to the ledge rather than appearing on it.
                    if !settleFoot(&leg, i, to: target, dt: dt) {
                        let g = groundFoot(leg.foot)
                        leg.foot = leg.foot.distance(to: g) > 2 ? approach(leg.foot, g, 14, maxSpeed: 240, dt) : g
                    }
                }
                legs[i] = leg
            }
            return
        }

        // On a line: the hind legs hold it and the front ones hang free, or
        // all eight climb it hand over hand.
        if onLine {
            if legController != .hang { startLineLegs() }
            legController = .hang
            if mantle != nil { updateMantleLegs() } else { updateLineLegs(dt: dt) }
            return
        }

        // Feet are free while the body is well round toward the front view;
        // a mere glance keeps them stepping.
        // (A little either way of the switch-over, so a body hovering about
        // it — following the pointer — does not flap between the two.)
        // On the move it steps however far round it is — walking sideways
        // face on to you, or swinging through the front view as it doubles
        // back — or the body would glide along on frozen legs.
        let onTheMove = mode == .attached && speed > 1 && activity != .hop
        // (Nor, stopped for a moment on its way, however far round to you
        // it has come: it is still walking, and stands as it walks.)
        let midWalk = mode == .attached && Spider.onFoot.contains(activity) && !Spider.debugNoBodyLanguage
        guard legMode == .planted, onTheMove || midWalk || (facing == m && profile > (legController == .posed ? 0.55 : 0.45)) else {
            legController = .posed
            if mode == .attached, activity == .groove {
                updateGrooveLegs(dt: dt, dTheta: dTheta, overFeet: overFeet)
                return
            }
            // On a ledge, a gesture is eased into from wherever the feet
            // were, and eased out of back to standing before it ends.
            let eased = mode == .attached && Spider.easedPoses.contains(activity)
            let rise = eased ? smoothstep(clamp((t - activityStarted) / Spider.poseEaseIn, 0, 1)) : 1
            let fall = eased && activityDur > Spider.poseEaseOut * 2 && activity != .sleep
                ? smoothstep(clamp((activityDur - activityTime) / Spider.poseEaseOut, 0, 1)) : 1
            // In the air in a hop, the feet are placed outright, off the
            // ledge under them: a spring would have them either stay stuck
            // to it or snap to the body's pace the moment they left it.
            if mode == .attached, activity == .hop, case let (stage, v) = hopPhase(), stage == 2 {
                // They peel off after the body has gone — from a standstill —
                // come up under it, and are back down on the ledge, gently,
                // just before it lands on them.
                let peel = pow(v, 1.25)
                let up = sin(peel * .pi) * sin(peel * .pi)
                for i in legs.indices {
                    let rest = SpiderRenderer.rig(i, profile: profile, look: look).foot
                    let ground = groundFoot(rest, spread: true, leg: i)
                    let x = lerp(ground.x, legs[i].hip.x + (rest.x - legs[i].hip.x) * 0.7, up * 0.6)
                    legs[i].foot = V2(x, ground.y + up * Spider.hopFeet)
                    legs[i].footVel = .zero
                    legs[i].lift = up
                    legs[i].swinging = false
                    legs[i].settle = -1
                }
                return
            }
            for i in legs.indices {
                let posed = poseTarget(i)
                var target = groundPose(i, posed)
                // Into and out of the pose the foot swings round the hip, as
                // a leg does — never along a straight line that could take
                // it right past the hip, where the knee has no way to bend.
                if rise < 1 { target = Spider.swing(legs[i].poseFrom, target, about: legs[i].hip, rise) }
                if fall < 1 {
                    let stand = groundPose(i, SpiderRenderer.rig(i, profile: profile, look: look).foot)
                    target = Spider.swing(stand, target, about: legs[i].hip, fall)
                }
                // A foot on the ledge stays where it is in the world while
                // the body moves over it — coming down out of a landing,
                // lifting for a wave, swinging round — and the spring only
                // eases it to its spot; a raised foot goes with the body.
                if mode == .attached, posed.y <= legs[i].rest.y + 1.5 {
                    legs[i].foot = legs[i].foot.rotated(by: -dTheta) - overFeet
                    if watchingPlanted, rise >= 1, fall >= 1 {
                        var leg = legs[i]
                        if keepPlanted(&leg, i, to: target, dt: dt) {
                            legs[i] = leg
                            continue
                        }
                    }
                }
                // Soft, well-damped spring, so every pose change eases — but
                // a drumming front leg has to keep up with the beat.
                // Legs folding into a ball, and shooting out to catch it
                // at the end, are quicker than a gesture.
                let quick = activity == .drum && mode == .attached && i % 4 == 0
                let rolling = activity == .roll && mode == .attached
                // Landing (swinging round to face the other way, say), a
                // foot meant for the ledge gets there with the body.
                let planting = absorbingLanding && posed.y <= legs[i].rest.y + 1.5
                let (k, c): (CGFloat, CGFloat) = quick ? (1800, 60)
                    : rolling ? (rollPhase().phase == 2 ? (750, 42) : (420, 34))
                    : planting ? (900, 60) : (200, 26)
                let a = (target - legs[i].foot) * k - legs[i].footVel * c
                legs[i].footVel += a * dt
                legs[i].foot += legs[i].footVel * dt
                legs[i].lift = approach(legs[i].lift, 0, 6, dt)
                legs[i].swinging = false
                legs[i].settle = -1
            }
            return
        }

        // Where a foot aims to touch down: half a stance ahead of its rest
        // position, so over the stance it drifts back through the rest pose.
        // (A step still in flight from another controller's clock, this
        // one frame before the hand-off drops it, goes the way it walks.)
        let ownSteps = legController == .gait
        legController = .gait
        if naturalWalk {
            updateNaturalGait(dt: dt, profile: profile, m: m, dTheta: dTheta, deltaLocal: deltaLocal, overFeet: overFeet, ownSteps: ownSteps)
            return
        }
        if refinedWalk {
            updateRefinedGait(dt: dt, profile: profile, m: m, dTheta: dTheta, deltaLocal: deltaLocal, overFeet: overFeet, ownSteps: ownSteps)
            return
        }
        let stride = strideNow
        let landAhead = stride * (1 - duty) * 0.5
        let walking = speed > 1
        // Which way along the sprite's x the body is going: backwards while
        // it swings round through the front view to the way it now walks.
        let fwd: CGFloat = mode == .attached && walkDir * m < 0 ? -1 : 1

        for i in legs.indices {
            var leg = legs[i]
            leg.footVel = .zero
            var ph = (gaitPhase + leg.phase).truncatingRemainder(dividingBy: 1)
            // (A step handed over at the front view, on its own clock, may
            // have begun just before this slot's window came round.)
            if leg.swingShift != 0, leg.swinging, ph > 0.75 { ph -= 1 }
            let swingEnd = duty + leg.swingShift

            if ph >= duty { leg.skipSwing = false }
            if walking, ph < duty, !leg.swinging, ph > duty * 0.3 { leg.skipSwing = true }
            if walking && ph < swingEnd && !leg.skipSwing {
                leg.settle = -1
                if !leg.swinging {
                    leg.swinging = true
                    leg.swingFrom = leg.foot
                    leg.swingPh0 = ph
                    leg.swingDir = fwd
                } else {
                    if !ownSteps { leg.swingDir = fwd }
                    // The step runs over the ground, not with the body: it
                    // leaves from the spot the foot stood on, which stays
                    // where it is while the body carries on over it.
                    leg.swingFrom = leg.swingFrom.rotated(by: -dTheta) - deltaLocal
                }
                let u = clamp((ph - leg.swingPh0) / max(swingEnd - leg.swingPh0, 0.01), 0, 1)
                // Land on the edge itself, wherever that is relative to the
                // body — at the spot on the ground that will be there at
                // touchdown, not where it is now. Both ends of the step are
                // then still on the ground, so the foot lifts off and sets
                // down at rest instead of being yanked from a standstill to
                // the body's pace and stopped dead again.
                let restNow = SpiderRenderer.rig(i, profile: profile, look: look).foot
                let ahead = (swingEnd - ph) * stride   // body travel before it lands
                let target = groundFoot(restNow + travelLocal * leg.swingDir * (landAhead + ahead), spread: true, leg: i)
                let base = stepPath(i, from: leg.swingFrom, to: target, u: u)
                // Eased off and onto the ledge at both ends of the arc.
                leg.lift = pow(sin(u * .pi), 1.5)
                // The foot lifts clear of the ledge on a shallow arc — higher
                // when it is being bouncy or walking on tiptoe.
                let stepHeight: CGFloat = gaitStyle == .bouncy ? 8 : (gaitStyle == .tiptoe ? 6.5 : 5)
                leg.foot = base + V2(0, leg.lift * stepHeight)
            } else {
                leg.swinging = false
                leg.swingShift = 0
                leg.lift = approach(leg.lift, 0, 16, dt)
                if walking {
                    // Stance: hold station on the ledge while the body moves
                    // — unless the foot is still in the air from before, in
                    // which case it steps down first.
                    let restNow = SpiderRenderer.rig(i, profile: profile, look: look).foot
                    let rest = groundFoot(restNow, spread: true, leg: i)
                    // (Likewise a front foot left well behind its own hip —
                    // still on the floor as the body came round off a wall
                    // onto it — which no stride puts there: it steps up.)
                    // (Past where a stride this long ever trails it: at a
                    // run, and small, the strides are long for its size.)
                    let trails = min(leg.hip.x, leg.rest.x - stride * (1 - duty) * 0.5)
                    let stranded = fwd > 0 && i % 4 == 0 && leg.foot.x < trails - Spider.strandedBehind
                    if leg.settle >= 0 || leg.foot.y > max(rest.y, leg.hip.y) + 5 || stranded {
                        _ = settleFoot(&leg, i, to: rest, dt: dt)
                        legs[i] = leg
                        continue
                    }
                    leg.foot = leg.foot.rotated(by: -dTheta) - deltaLocal
                    let g = groundFoot(leg.foot)
                    leg.foot = leg.foot.distance(to: g) > 2 ? approach(leg.foot, g, 14, maxSpeed: 240, dt) : g
                    // Never let a foot be dragged past what the leg can reach.
                    // (Turned toward you the feet stand wider: face on, walking
                    // sideways, a stride takes them that much further out.)
                    let reach = leg.foot - leg.hip
                    let maxReach = max((leg.rest - leg.hip).length, (restNow - leg.hip).length) * 1.4
                    if reach.length > maxReach {
                        leg.foot = groundFoot(leg.hip + reach.normalized * maxReach, leg: i)
                    }
                } else {
                    standStill(&leg, i, profile: profile, dTheta: dTheta, overFeet: overFeet, dt: dt)
                }
            }
            legs[i] = leg
        }
    }

    /// Standing: settle onto the rest pose — on the edge, which round a
    /// corner is not where the rest pose says — with a little idle shuffle
    /// so it never looks frozen. A foot left well off its spot (mid-stride
    /// when it stopped, or up in the air from a wave) takes one small step
    /// there; the legs go one at a time, in gait order.
    private func standStill(_ leg: inout Leg, _ i: Int, profile: CGFloat, dTheta: CGFloat, overFeet: V2, dt: CGFloat) {
        var rest = SpiderRenderer.rig(i, profile: profile, look: look).foot
        rest.x += leg.wobble.value(t * 0.8) * 0.5
        // (Coming down onto a ledge still out of reach, the step
        // is to the ledge itself, reached for as the body comes
        // down — as in `land`.)
        let near = reachableSpot(rest, spread: true, leg: i)
        let target = near.onGround || !absorbingLanding ? near.point : groundFoot(rest, spread: true)
        // A planted foot holds its place in the world while the
        // body moves over it — coming down and lurching out of
        // a landing, leaning, breathing — the leg giving, never
        // dragged into the ledge with it; then eases to its spot.
        if leg.settle < 0 {
            leg.foot = leg.foot.rotated(by: -dTheta) - overFeet
            let reach = leg.foot - leg.hip
            var maxReach = (leg.rest - leg.hip).length * 1.4
            // (Turned toward you the feet stand wider — stopped for a moment
            // on its way round to you, say — as `updateLegControllers` has
            // them walking.)
            if !Spider.debugNoBodyLanguage {
                let layout = SpiderRenderer.rig(i, profile: profile, look: look).foot
                maxReach = max(maxReach, (layout - leg.hip).length * 1.4)
            }
            if reach.length > maxReach { leg.foot = groundFoot(leg.hip + reach.normalized * maxReach, leg: i) }
        }
        if watchingPlanted, keepPlanted(&leg, i, to: target, dt: dt) { return }
        // One leg at a time unless a foot is well out of place.
        let othersBusy = !absorbingLanding && legs.contains(where: { $0.settle >= 0 }) && leg.settle < 0
        if othersBusy && leg.foot.distance(to: target) <= 14 || !settleFoot(&leg, i, to: target, dt: dt) {
            leg.foot = approach(leg.foot, target, absorbingLanding ? 30 : 9, dt)
        }
    }

    // MARK: - The natural walk

    /// Walking the natural way (`Gait.natural`, picked in the studio): each
    /// leg is drawn at its own true length, bent only at the knee, so every
    /// foot's stride is fitted to what that leg can really reach from its
    /// hip — the short legs under the chin set how far a stance can run,
    /// and past that it steps quicker rather than stretching a leg.
    /// Steps ripple from the back legs to the front ones. Ambling slowly
    /// or sneaking it walks a leg at a time down each side (a wave gait);
    /// at a walk the legs go in two sets of four, alternating (a tetrapod),
    /// and the quicker it goes the more of each step is spent in the air.
    /// A step lifts quickly, folds in toward the body on the way forward
    /// and comes down gently where the foot will be when it lands; the
    /// front pair step higher, feeling their way. Stopped, the feet tidy
    /// up with a small step each, instead of sliding into place.
    private var naturalWalk: Bool { gait.natural && mode == .attached }
    /// 0 a leg at a time (slow), 1 the alternating sets of four.
    private var natPattern: CGFloat = 1
    /// How much of each step cycle a foot spends in the air.
    private var natDuty: CGFloat = 0.36
    /// The longest stance, in sprite units, every leg can take right now.
    private var natSweep: CGFloat = 20
    /// Each knee's share of the way to being worked out from the leg's
    /// true bone lengths (see `updateKnees`): eased in and out as the
    /// natural walk takes the legs and hands them on.
    private var natKnee: [CGFloat] = Array(repeating: 0, count: SpiderRenderer.legCount)
    /// How far out toward full stretch a leg may be put down or carried:
    /// never locked straight.
    private static let natReach: CGFloat = 0.88
    /// Round a corner, how far out a planted foot is left before it steps.
    private static let natCornerReach: CGFloat = 0.92
    /// How far past its own hip, to the other side, a foot may go, as a
    /// share of its reach: a front foot is not dragged back under the body.
    private static let natCross: CGFloat = 0.3
    /// The least reach, as a share of the leg, a foot stands at walking.
    private static let natWork: CGFloat = 0.5
    /// Between each leg and the one in front of it on the same side, in
    /// the alternating gait: the ripple from the back to the front.
    private static let natRipple: CGFloat = 0.05
    /// Below this pace (sprite units a second) it walks a leg at a time,
    /// above the other, the alternating gait.
    private static let natSlow: CGFloat = 30
    private static let natBrisk: CGFloat = 38
    /// The body's height over its legs with the average leg this far up.
    private static let natBobLevel: CGFloat = 0.2
    /// How far off its spot a foot is left, standing, before it steps.
    private static let natTidySlack: CGFloat = 2.5

    /// Where in the cycle leg `i` begins its step, blended between the two
    /// patterns by `natPattern`.
    private func natStart(_ i: Int) -> CGFloat {
        let near = i < 4, k = i % 4
        let back = CGFloat(3 - k)
        let tetra: CGFloat = ((k % 2 == 0) == near ? 0 : 0.5) + back * Spider.natRipple
        let wave: CGFloat = (near ? 0 : 0.5) + back * 0.25
        var d = (wave - tetra).truncatingRemainder(dividingBy: 1)
        if d > 0.5 { d -= 1 } else if d < -0.5 { d += 1 }
        return tetra + d * (1 - natPattern)
    }

    /// Leg `i`'s reach along the ground, in sprite x: from `lo` to `hi` its
    /// foot can stand without the leg straightening, for the hip where it
    /// is drawn and the ground `groundY` below it. `rest` is where it
    /// stands still, `len` the leg's length and `hip` its drawn hip.
    private func natRange(_ i: Int, profile: CGFloat, groundY: CGFloat) -> (lo: CGFloat, hi: CGFloat, rest: CGFloat, len: CGFloat, fold: CGFloat, hip: V2) {
        let r = SpiderRenderer.rig(i, profile: profile, look: look)
        let hip = drawnHip(i, profile: profile)
        let thigh = (r.knee - r.hip).length, shin = (r.foot - r.knee).length
        let len = thigh + shin
        let most = len * Spider.natReach
        // (Nor can a foot come in closer than the leg folds: a short thigh
        // on a long shin keeps its foot well out from the hip.)
        let fold = abs(thigh - shin) + len * 0.15
        let h = clamp(hip.y - groundY, 2, most * 0.9)
        let x = (most * most - h * h).squareRoot()
        // A long leg works well out from its hip — the front ones reaching
        // on ahead, the hind ones trailing — not folded up under the body,
        // where lifting the foot would flick the knee up.
        let work = max(fold, len * Spider.natWork)
        let inner = (max(work * work - h * h, 0)).squareRoot()
        let out: CGFloat = r.foot.x >= r.hip.x ? 1 : -1
        let a = hip.x + out * x, b = inner > 0 ? hip.x + out * min(inner, x * 0.5) : hip.x - out * x * Spider.natCross
        return (min(a, b), max(a, b), r.foot.x, len, fold, hip)
    }

    /// `p`, a spot on the ground, brought in along the ground toward the
    /// spot under `hip` until the leg can reach it without straightening;
    /// if even that is too far, as near as the leg goes.
    private func natFit(_ p: V2, hip: V2, most: CGFloat, out: CGFloat? = nil) -> V2 {
        guard p.distance(to: hip) > most else { return p }
        let under = groundFoot(V2(hip.x, p.y))
        var fit = hip + (p - hip).normalized * most
        if under.distance(to: hip) <= most {
            var lo: CGFloat = 0, hi: CGFloat = 1
            for _ in 0..<10 {
                let mid = (lo + hi) / 2
                if V2.lerp(p, under, mid).distance(to: hip) > most { lo = mid } else { hi = mid }
            }
            fit = V2.lerp(p, under, hi)
        }
        // (Round a corner the way in to the spot under the hip cuts across
        // it — through the window, or out over the drop — and the spot on
        // it is nowhere on the ground: the leg swings in about its hip to
        // the ground instead.)
        if mode == .attached, let loop = map.loop(anchor.loopID), !loop.edge.isEmpty,
           abs(surfaceSide(toWorld(fit), loop)) > 0.5 * max(config.scale, 0.05),
           let q = swingToGround(hip: hip, toward: p, span: most, out: out, loop) {
            return q
        }
        return fit
    }

    /// The lift of a natural step, `u` of the way through it: up quickly,
    /// highest a little before half way, and down gently — leaving the
    /// ledge and coming back to it at rest.
    private static func natLift(_ u: CGFloat) -> CGFloat {
        let s = sin(pow(clamp(u, 0, 1), 0.9) * .pi)
        return s * s
    }

    private func updateNaturalGait(dt: CGFloat, profile: CGFloat, m: CGFloat, dTheta: CGFloat, deltaLocal: V2, overFeet: V2, ownSteps: Bool) {
        let scale = max(config.scale, 0.05)
        let walking = speed > 1
        let fwd: CGFloat = walkDir * m < 0 ? -1 : 1

        // Which pattern: by the pace it means to go (kept through a pause).
        let pace = targetSpeed / scale
        if targetSpeed > 1 {
            let want: CGFloat = pace < Spider.natSlow ? 0 : (pace > Spider.natBrisk ? 1 : (natPattern > 0.5 ? 1 : 0))
            natPattern = approach(natPattern, want, 2.2, dt)
            if abs(natPattern - want) < 0.002 { natPattern = want }
        }
        // The quicker the steps come, the more of each is spent in the air
        // (a leg can only swing forward so fast); a leg at a time, little.
        let cadence = speed / scale / max(strideNow, 1)
        natDuty = lerp(0.2, lerp(0.36, 0.46, clamp((cadence - 2.5) / 3, 0, 1)), natPattern)
        let duty = natDuty

        // What each leg can reach from where its hip is now.
        var groundY = groundFoot(V2(0, SpiderRenderer.ground)).y
        // (Over the outside of a corner the ground under the body falls away
        // below the line it stands over, and a range worked out from there
        // would let a leg out past its own hip; each is worked out as along a
        // ledge, and its foot put onto the ground round the corner from there.)
        let ledge = SpiderRenderer.ground - refRide / scale
        if groundY < ledge - 0.5 { groundY = ledge }
        let ranges = legs.indices.map { natRange($0, profile: profile, groundY: groundY) }
        natSweep = max(ranges.map { $0.hi - $0.lo }.min()! * 0.9, 6)
        let stride = strideNow
        let sweep = min(stride * (1 - duty), natSweep)
        // How far the gait clock goes on in a frame, and how long a step is.
        let phStep = speed / (stride * scale) * dt
        let swingTime = dt > 0 && phStep > 0 ? duty * dt / phStep : 1

        // Front legs step highest, feeling their way; sneaking, every step
        // is high and careful.
        let style: CGFloat = gaitStyle == .bouncy ? 1.4 : (gaitStyle == .tiptoe ? 1.25 : (gaitStyle == .lumber ? 0.8 : 1))
        let careful: CGFloat = activity == .sneak ? 1.3 : 1
        let heights: [CGFloat] = [5.5, 3.6, 3.2, 3.6]

        for i in legs.indices {
            var leg = legs[i]
            leg.footVel = .zero
            let rg = ranges[i]
            let most = rg.len * Spider.natReach
            // The middle of this leg's stance: where it stands still, or as
            // near that as leaves room for the whole stance within reach.
            let c = rg.lo + sweep / 2 <= rg.hi - sweep / 2 ? clamp(rg.rest, rg.lo + sweep / 2, rg.hi - sweep / 2) : (rg.lo + rg.hi) / 2
            let groundLine = SpiderRenderer.rig(i, profile: profile, look: look).foot.y
            var ph = (gaitPhase - natStart(i)).truncatingRemainder(dividingBy: 1)
            if ph < 0 { ph += 1 }
            if leg.swingShift != 0, leg.swinging, ph > 0.75 { ph -= 1 }
            let swingEnd = duty + leg.swingShift

            if ph >= duty { leg.skipSwing = false }
            if walking, ph < duty, !leg.swinging, ph > duty * 0.3 { leg.skipSwing = true }
            if walking && ph < swingEnd && !leg.skipSwing {
                leg.settle = -1
                if !leg.swinging {
                    leg.swinging = true
                    leg.swingFrom = leg.foot
                    leg.swingPh0 = ph
                    leg.swingDir = fwd
                } else {
                    if !ownSteps { leg.swingDir = fwd }
                    leg.swingFrom = leg.swingFrom.rotated(by: -dTheta) - deltaLocal
                }
                // (Timed to be down on the last frame of its window, however
                // few frames a quick step gets.)
                let last = max(swingEnd - phStep, leg.swingPh0 + 0.01)
                let u = clamp((ph - leg.swingPh0) / (last - leg.swingPh0), 0, 1)
                // Down where the front of its stance will be by the time it
                // lands — within reach then — which is that much further on
                // now, while the body is still on its way there.
                let ahead = max(last - ph, 0) * stride
                let target = groundFoot(V2(c + leg.swingDir * (sweep / 2 + ahead), groundLine), spread: true, leg: i)
                var foot = V2.lerp(leg.swingFrom, target, easeInOutSine(u))
                leg.lift = Spider.natLift(u)
                // (A step over in a few frames is a lower one: the foot has
                // no time to go high and come down again.)
                let quick = clamp(swingTime / 0.16, 0.6, 1)
                let height = heights[i % 4] * style * careful * clamp(sweep / 16, 0.7, 1.2) * quick
                foot.y += leg.lift * height
                // The leg folds in toward the body on its way forward.
                let s = sin(u * .pi)
                foot += (rg.hip - foot) * (0.1 * s * s)
                let d = foot.distance(to: rg.hip)
                if d > most { foot = rg.hip + (foot - rg.hip) * (most / d) }
                if d < rg.fold { foot = rg.hip + (foot - rg.hip) * (rg.fold / max(d, 0.01)) }
                leg.foot = foot
                if u >= 1 { leg.lift = 0 }
            } else {
                leg.swinging = false
                leg.swingShift = 0
                leg.lift = approach(leg.lift, 0, 16, dt)
                let spot = natFit(groundFoot(V2(c + fwd * sweep / 2, groundLine), spread: true, leg: i), hip: rg.hip, most: most,
                                  out: rg.rest >= SpiderRenderer.rig(i, profile: profile, look: look).hip.x ? 1 : -1)
                if walking {
                    // Stance: held where it stands on the ledge while the
                    // body goes on over it.
                    if leg.settle >= 0 || leg.foot.y > max(groundLine, rg.hip.y) + 5 {
                        _ = settleFoot(&leg, i, to: spot, dt: dt)
                        legs[i] = leg
                        continue
                    }
                    leg.foot = leg.foot.rotated(by: -dTheta) - deltaLocal
                    let g = groundFoot(leg.foot)
                    leg.foot = leg.foot.distance(to: g) > 2 ? approach(leg.foot, g, 14, maxSpeed: 240, dt) : g
                    // Left behind — it sat a step out, the pace picked up, the
                    // body turned a corner over it — it steps forward now,
                    // out of turn, before the leg would have to stretch.
                    let behind = fwd * (leg.foot.x - c) < -(sweep / 2 + 4)
                    let d = leg.foot.distance(to: rg.hip)
                    // (Round a corner, before it is near straight: a leg along
                    // a ledge never stands out past `natReach`. Nor is it left
                    // carried on ahead of where it stands — the body rolling
                    // round the corner over it swings it on round its hip, to
                    // where its knee would bend the wrong way.)
                    let cornered = footCornered(i) > 0
                    let longest = rg.len * (cornered ? Spider.natCornerReach : 0.97)
                    let carried = cornered && fwd * (leg.foot.x - c) > sweep / 2 + 4
                    if behind || carried || d > longest || d < rg.fold * 0.9 {
                        leg.settle = 0
                        leg.swingFrom = leg.foot
                        leg.settleTo = spot
                        _ = settleFoot(&leg, i, to: spot, dt: dt)
                    }
                } else if absorbingLanding || watchingPlanted && !Spider.onFoot.contains(activity) {
                    standStill(&leg, i, profile: profile, dTheta: dTheta, overFeet: overFeet, dt: dt)
                } else {
                    // (Stopped for a moment on its way — turned round to you,
                    // or not — it stands as it walks: a foot steps to its
                    // spot, never slides there.)
                    natTidy(&leg, i, profile: profile, dTheta: dTheta, overFeet: overFeet, hip: rg.hip, most: most, dt: dt)
                }
            }
            legs[i] = leg
        }
    }

    /// Standing, walking the natural way: every foot stays put where it is
    /// on the ledge, and one left off its spot — the walk ended mid-stride
    /// — takes a small step there, two legs at a time at most and never
    /// two neighbours together, rather than sliding over.
    private func natTidy(_ leg: inout Leg, _ i: Int, profile: CGFloat, dTheta: CGFloat, overFeet: V2, hip: V2, most: CGFloat, dt: CGFloat) {
        var rest = SpiderRenderer.rig(i, profile: profile, look: look).foot
        rest.x += leg.wobble.value(t * 0.8) * 0.5
        let target = natFit(reachableSpot(rest, spread: true, leg: i).point, hip: hip, most: most,
                            out: rest.x >= SpiderRenderer.rig(i, profile: profile, look: look).hip.x ? 1 : -1)
        if leg.settle >= 0 {
            _ = settleFoot(&leg, i, to: target, dt: dt)
            return
        }
        leg.foot = leg.foot.rotated(by: -dTheta) - overFeet
        let g = groundFoot(leg.foot)
        let inAir = leg.foot.distance(to: g) > 2
        let off = leg.foot.distance(to: target)
        let busy = legs.indices.filter { $0 != i && legs[$0].settle >= 0 }
        let neighbour = busy.contains { ($0 < 4) == (i < 4) && abs($0 % 4 - i % 4) == 1 }
        if off > Spider.natTidySlack, inAir || off > 14 || (busy.count < 2 && !neighbour) {
            leg.settle = 0
            leg.swingFrom = leg.foot
            leg.settleTo = target
            _ = settleFoot(&leg, i, to: target, dt: dt)
        } else {
            leg.foot = inAir ? approach(leg.foot, g, 14, maxSpeed: 240, dt) : g
        }
    }

    // MARK: - The refined walk

    /// Walking the refined way (`Gait.motion == .refined`, picked in the
    /// studio): the classic walk — its long, even strides, its arching
    /// steps, the way it stands — with every leg drawn at its own true
    /// length the whole time, bent only at the knee, along a ledge and
    /// round its corners alike.
    ///
    /// What keeps a leg whole is where its foot goes. Each leg works
    /// between its knee bent no tighter than `refFold` and opened no wider
    /// than `refOpen`; its stance is fitted inside that, and the stride is
    /// as long as all eight can take — past that it steps quicker. A foot
    /// is put down where it will stand under the body half way through its
    /// stance, in the frame the body will have then: along a straight
    /// ledge that is the classic walk's own spot; round a corner the body
    /// will have turned, and the foot goes where the turned body wants it.
    /// A planted foot about to be left out of reach steps on, out of turn,
    /// before its leg would have to stretch.
    ///
    /// A step leaves the ground and comes back to it at rest, rises
    /// quickly, folds in toward the body as the knee comes up, and reaches
    /// on — over the edge of whatever it is walking round, never through
    /// it. Steps ripple from the back legs to the front, slower and more
    /// spread out the more it dawdles; the quicker it goes, the more of
    /// each step is spent in the air. The body rides its legs, settling a
    /// little as a set of them comes up and rising as they take its weight
    /// again; and in an inside corner it tucks in close, so its legs reach
    /// both walls.
    private var refinedWalk: Bool { gait.motion == .refined && mode == .attached }
    /// How much of each step cycle a foot spends in the air, and how far
    /// apart in the cycle a leg steps from the one behind it: both eased.
    private var refSwing: CGFloat = 0.38
    private var refRipple: CGFloat = 0.05
    /// The longest stance every leg can take right now, in sprite units.
    private var refSweep: CGFloat = 20
    /// The body's height over the line it stands on, in world points — its
    /// bob, lift and breath: set by `updateAttached`.
    private var refRide: CGFloat = 0
    /// How far the body has tucked into an inside corner, in world points.
    private var refTuck = Spring(0, stiffness: 150, damping: 25)
    /// How long it has been standing, walking the refined way.
    private var refStill: CGFloat = 0
    /// How much each leg is giving right now (see `refGive`): read off how
    /// far out its foot is while it stands on it, and carried smoothly from
    /// where a step leaves to where it lands while it steps — so a leg's
    /// length never jumps, however quickly its foot moves.
    private var refGiveNow: [CGFloat] = Array(repeating: 1, count: SpiderRenderer.legCount)
    /// The tightest and the widest a knee bends walking — the angle between
    /// thigh and shin — and the furthest it is ever let go either way.
    private static let refFold: CGFloat = 28 * .pi / 180
    private static let refOpen: CGFloat = 140 * .pi / 180
    private static let refFoldMost: CGFloat = 12 * .pi / 180
    private static let refOpenMost: CGFloat = 168 * .pi / 180
    /// How far past the spot under its own hip a foot may go, as a share of
    /// its leg: a front foot is not dragged back under the body.
    private static let refCross: CGFloat = 0.12
    /// How high each pair steps, front to back, in sprite units: the front
    /// pair highest, feeling their way.
    private static let refHeight: [CGFloat] = [6.2, 4.0, 3.6, 4.4]
    /// How far each pair draws its foot in toward its hip at the top of a step.
    private static let refDraw: [CGFloat] = [0.06, 0.06, 0.05, 0.06]
    /// The longest a step ever takes, however slowly it is going — or if
    /// it stops with a foot in the air.
    private static let refLongestStep: CGFloat = 0.42
    /// The average lift of the legs walking: the body's height over its
    /// legs with them this far up.
    private static let refBobLevel: CGFloat = 0.17

    /// How much longer than its own a leg's bones are drawn, walking the
    /// refined way, with its foot `reach` times as far from its hip as it
    /// stands: not at all out to there, and then a little, more the further
    /// out — `refGiveMost` at most, `refGiveOver` further out than it
    /// stands — so a long reach keeps the arch in the leg, as the classic
    /// walk's does, rather than straightening it into a stick. A smooth
    /// give, never a jump, and none at all wherever any other way of
    /// standing has the leg.
    private static let refGiveMost: CGFloat = 0.12
    private static let refGiveOver: CGFloat = 0.35
    private static func refGive(_ reach: CGFloat) -> CGFloat {
        1 + refGiveMost * smoothstep((reach - 1) / refGiveOver)
    }

    /// Hip to foot for leg bones `a` and `b` (the rest span `rest` apart),
    /// bent to `angle`, with the give they have there (see `refGive`).
    private static func refSpanGiving(_ a: CGFloat, _ b: CGFloat, rest: CGFloat, _ angle: CGFloat) -> CGFloat {
        var d = refSpan(a, b, angle)
        for _ in 0..<4 {
            let g = refGive(d / max(rest, 1))
            d = refSpan(a * g, b * g, angle)
        }
        return d
    }

    /// One leg as the refined walk sees it this frame, in sprite units.
    private struct RefLeg {
        /// Where it is drawn from, its two bones, and where it stands still.
        var hip: V2
        var thigh: CGFloat
        var shin: CGFloat
        var rest: V2
        /// Hip to foot: the span it works in, walking, and the most it is
        /// ever folded up or opened out to.
        var lo: CGFloat
        var hi: CGFloat
        var least: CGFloat
        var most: CGFloat
        /// +1 for a leg whose foot stands out ahead of its hip, -1 behind.
        var out: CGFloat
        /// Which way its knee bends: +1 to the left of hip-to-foot, -1 right.
        var side: CGFloat
        /// Along the line it stands over: where the foot can be, and the
        /// middle of its stance.
        var from: CGFloat
        var to: CGFloat
        var centre: CGFloat = 0
        /// Hip to foot as it stands still.
        var restSpan: CGFloat = 1
        /// Hip to foot, walking along a ledge: at most (at the far end of its
        /// stance), and half way through it.
        var walkSpan: CGFloat = 1
        var midSpan: CGFloat = 1
        var len: CGFloat { thigh + shin }
        /// How much it gives with its foot at `p` (see `refGive`).
        func give(at p: V2) -> CGFloat { Spider.refGive(p.distance(to: hip) / max(restSpan, 1)) }
        /// The furthest it is ever opened out to, giving `give`.
        func most(giving give: CGFloat) -> CGFloat { Spider.refSpan(thigh * give, shin * give, Spider.refOpenMost) }
    }

    /// Hip to foot, for a leg with these bones bent to this angle.
    private static func refSpan(_ a: CGFloat, _ b: CGFloat, _ angle: CGFloat) -> CGFloat {
        max(a * a + b * b - 2 * a * b * cos(angle), 0).squareRoot()
    }

    private func refLeg(_ i: Int, profile: CGFloat, ground: CGFloat) -> RefLeg {
        let r = SpiderRenderer.rig(i, profile: profile, look: look)
        let hip = drawnHip(i, profile: profile)
        let a = max((r.knee - r.hip).length, 1), b = max((r.foot - r.knee).length, 1)
        let rest = (r.foot - r.hip).length
        let lo = Spider.refSpan(a, b, Spider.refFold), hi = Spider.refSpanGiving(a, b, rest: rest, Spider.refOpen)
        let out: CGFloat = r.foot.x >= r.hip.x ? 1 : -1
        // How far out from under the hip, along the line, the foot can be
        // within that span.
        let h = clamp(hip.y - ground, 1, hi * 0.95)
        let far = (hi * hi - h * h).squareRoot()
        let near = lo > h ? (lo * lo - h * h).squareRoot() : -(a + b) * Spider.refCross
        let x0 = hip.x + out * near, x1 = hip.x + out * far
        return RefLeg(hip: hip, thigh: a, shin: b, rest: r.foot, lo: lo, hi: hi,
                      least: Spider.refSpan(a, b, Spider.refFoldMost),
                      most: Spider.refSpanGiving(a, b, rest: rest, Spider.refOpenMost),
                      out: out, side: (r.foot - r.hip).cross(r.knee - r.hip) >= 0 ? 1 : -1,
                      from: min(x0, x1), to: max(x0, x1), restSpan: rest)
    }

    /// Where in the cycle leg `i` begins its step: two sets of four taking
    /// turns, each stepping from its back legs to its front ones.
    private func refStart(_ i: Int) -> CGFloat {
        let near = i < 4, k = i % 4
        return ((k % 2 == 0) == near ? 0 : 0.5) + CGFloat(3 - k) * refRipple
    }

    /// The body's path `dist` world points on from where it is now, the way
    /// it is walking: the point, which way the path runs there, its normal,
    /// and how far the body tucks into a corner there.
    private typealias RefPathPoint = (pos: V2, angle: CGFloat, normal: V2, tuck: CGFloat)
    private func refPath(ahead dist: CGFloat) -> RefPathPoint? {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return nil }
        var a = anchor
        var remaining = dist
        var guardCount = 0
        while remaining > 0.0001, guardCount < 8 {
            guardCount += 1
            let seg = loop.segs[a.segIdx]
            let lim = seg.limit(from: a.t, dir: walkDir)
            let room = walkDir > 0 ? lim - a.t : a.t - lim
            if remaining <= room { a.t += walkDir * remaining; break }
            a.t = lim
            remaining -= room
            guard walkDir > 0 ? lim >= seg.len - 0.01 : lim <= 0.01 else { break }
            let n = loop.segs.count
            let next = walkDir > 0 ? a.segIdx + 1 : a.segIdx - 1
            guard loop.closed || (next >= 0 && next < n) else { break }
            let w = (next + n) % n
            let entry: CGFloat = walkDir > 0 ? 0 : loop.segs[w].len
            guard loop.segs[w].isOpen(at: entry + (walkDir > 0 ? 0.5 : -0.5)) else { break }
            a.segIdx = w
            a.t = entry
        }
        guard let here = map.resolve(a, cornerRadius: Spider.cornerRadius * config.scale) else { return nil }
        return (here.pos, here.tangent.angle, here.normal, refTuckAt(here.pos))
    }

    /// How far into an inside corner the body tucks at `p`, a point on its
    /// path: about as much as the edge it walks is further from it there
    /// than it stands off a straight edge — so its legs, at their own
    /// lengths, reach the walls either side.
    private func refTuckAt(_ p: V2) -> CGFloat {
        guard let loop = map.loop(anchor.loopID), !loop.edge.isEmpty else { return 0 }
        var d = CGFloat.greatestFiniteMagnitude
        for e in loop.edge where e.len > 0.5 { d = min(d, projectOnSegment(p, e.a, e.b).dist) }
        guard d < .greatestFiniteMagnitude else { return 0 }
        return clamp((d - map.standoff) * 1.1, 0, map.standoff * 0.7)
    }

    /// Where the body will be once it has gone `dist` world points on, and
    /// how much further round it will have turned: along a straight ledge
    /// simply that much further along; round a corner, turned with the
    /// path and tucked into it as the body will be. Nil off any path.
    private func refFrame(ahead dist: CGFloat, from now: RefPathPoint?) -> (pos: V2, turn: CGFloat)? {
        guard let now, let then = refPath(ahead: dist) else { return nil }
        let shift = (then.pos - then.normal * then.tuck) - (now.pos - now.normal * now.tuck)
        return (pos + shift, angleDelta(now.angle, then.angle))
    }

    /// `local` (sprite units) as the body will carry it once it has gone
    /// `dist` world points on (see `refFrame`), in sprite units as the body
    /// is now.
    private func refCarried(_ local: V2, ahead dist: CGFloat, from now: RefPathPoint?, fwd: CGFloat) -> V2 {
        guard let f = refFrame(ahead: dist, from: now) else { return local + V2(fwd * dist / max(config.scale, 0.05), 0) }
        return toLocal(f.pos + (toWorld(local) - pos).rotated(by: f.turn))
    }

    /// Where the body's own up-and-down line meets the edge it walks, for a
    /// body at world point `centre` turned `turn` further round than it is
    /// now: which stretch of edge, how far along it, and which way along it
    /// the body's front is (+1 or -1). Nil over a gap.
    private func refGroundUnder(centre c: V2, turn: CGFloat) -> (seg: Int, t: CGFloat, sign: CGFloat)? {
        guard let loop = map.loop(anchor.loopID), !loop.edge.isEmpty else { return nil }
        let s = max(config.scale, 0.05)
        let frame = heading + turn
        let down = V2(0, -1).rotated(by: frame), fwd = V2(mirrorSign, 0).rotated(by: frame)
        var hit: (seg: Int, t: CGFloat, r: CGFloat)?
        for (i, e) in loop.edge.enumerated() where e.len > 0.01 {
            let denom = down.cross(e.dir)
            guard abs(denom) > 1e-6, e.dir.perp.dot(down) < 0 else { continue }
            let w = e.a - c
            let r = w.cross(e.dir) / denom, along = w.cross(down) / denom
            guard r > -2 * s, along >= -0.01, along <= e.len + 0.01 else { continue }
            if hit == nil || r < hit!.r { hit = (i, clamp(along, 0, e.len), r) }
        }
        guard let h = hit, h.r < 90 * s else { return nil }
        return (h.seg, h.t, fwd.dot(loop.edge[h.seg].dir) >= 0 ? 1 : -1)
    }

    /// The point `dist` world points along a loop's edge from `t` along its
    /// piece `seg` — round its corners, as far as it goes.
    private static func refWalkEdge(_ loop: SurfaceLoop, seg: Int, t start: CGFloat, dist total: CGFloat) -> V2 {
        let n = loop.edge.count
        var i = seg, t = start, dist = total
        for _ in 0..<(n + 2) {
            let e = loop.edge[i]
            let room = dist >= 0 ? e.len - t : -t
            if abs(dist) <= abs(room) { t += dist; break }
            dist -= room
            let next = dist >= 0 ? i + 1 : i - 1
            if next < 0 || next >= n {
                guard loop.closed else { t = dist >= 0 ? e.len : 0; break }
            }
            i = (next + n) % n
            t = dist >= 0 ? 0 : loop.edge[i].len
        }
        let e = loop.edge[i]
        let p = e.point(at: clamp(t, 0, e.len))
        // (A window's corner is rounded: there, on the curve.)
        return loop.onRoundedCorner(p)?.point ?? p
    }

    /// Where leg `i` puts its foot down, stepping now: where it stands in
    /// the middle of its stance (`centre`), in the frame the body will be
    /// in half way through that stance — `ahead` is how far, in sprite
    /// units, the body goes on before the foot is down — onto the ground
    /// there, and within the leg's reach of where its hip will be as the
    /// foot comes down.
    private func refTarget(_ i: Int, _ g: RefLeg, ahead: CGFloat, half: CGFloat, fwd: CGFloat, ground: CGFloat, now: RefPathPoint?) -> V2 {
        let s = max(config.scale, 0.05)
        let hipDown = refCarried(g.hip, ahead: ahead * s, from: now, fwd: fwd)
        guard let f = refFrame(ahead: (ahead + half) * s, from: now), let loop = map.loop(anchor.loopID),
              let under = refGroundUnder(centre: f.pos, turn: f.turn) else {
            return refReach(groundFoot(refCarried(V2(g.centre, ground), ahead: (ahead + half) * s, from: now, fwd: fwd), leg: i), hip: hipDown, g)
        }
        // That far along the ground from under the body — its feet spread
        // round a corner as they are along a ledge — and then along it to
        // where the leg will stand as it does along a ledge: at its ordinary
        // span from the hip half way through the stance, and within its
        // reach as the foot comes down and as it lifts again. (Along a
        // straight edge that is simply the spot the walk puts it on.)
        let hipMid = refCarried(g.hip, ahead: (ahead + half) * s, from: now, fwd: fwd)
        let hipUp = refCarried(g.hip, ahead: (ahead + 2 * half) * s, from: now, fwd: fwd)
        let ideal = g.midSpan
        let axis = V2.angle(f.turn * mirrorSign)
        let axisDown = V2.angle((refFrame(ahead: ahead * s, from: now)?.turn ?? 0) * mirrorSign)
        func spot(_ shift: CGFloat) -> V2 {
            toLocal(Spider.refWalkEdge(loop, seg: under.seg, t: under.t, dist: (g.centre + shift) * s * under.sign))
        }
        func cost(_ shift: CGFloat) -> CGFloat {
            let p = spot(shift)
            // (Folded up is better than held out long: a spider going over
            // a lip grips it with its trailing legs folded tight.)
            let mid = (p.distance(to: hipMid) - ideal) / ideal
            var c = (mid > 0 ? 3 : 0.5) * mid * mid + 0.12 * (shift / ideal) * (shift / ideal)
            for hp in [hipDown, hipUp] {
                let d = p.distance(to: hp)
                let over = max(0, d - g.walkSpan * 1.06) / ideal, short = max(0, g.least * 1.3 - d) / ideal
                c += 20 * over * over + 8 * short * short
            }
            // (Never on the wrong side of its own hip — a hind foot put down
            // ahead of it, a front foot behind — where its knee would have to
            // bend the wrong way: along the body as it will be as the foot
            // comes down, and half way through its stance.)
            for (hp, ax) in [(hipDown, axisDown), (hipMid, axis)] {
                let along = (p - hp).dot(ax) * g.out + g.len * Spider.refCross
                if along < 0 { c += 30 * (along / ideal) * (along / ideal) }
            }
            // (Nor where its knee would go into the thing it is walking on:
            // in an inside corner, a front foot on the floor right at the
            // foot of the wall would bend its knee into the wall.)
            let give = g.give(at: p)
            let knee = Spider.twoBoneKnee(hip: hipMid, foot: p, thigh: g.thigh * give, shin: g.shin * give, side: g.side)
            if let o = refOut(knee) {
                let into = max(0, 2 * max(config.scale, 0.05) - o.out) / max(config.scale, 0.05) / ideal
                c += 12 * into * into
            }
            return c
        }
        var best = (shift: CGFloat(0), cost: cost(0))
        for k in -8...8 where k != 0 {
            let sh = CGFloat(k) * 3
            let c = cost(sh)
            if c < best.cost { best = (sh, c) }
        }
        // (Then between the samples, so it never hops from one to the next.)
        let a = cost(best.shift - 3), b = cost(best.shift + 3)
        let curve = a - 2 * best.cost + b
        let shift = curve > 1e-9 ? best.shift + clamp(1.5 * (a - b) / curve, -3, 3) : best.shift
        return refReach(groundFoot(spot(shift), leg: i), hip: hipDown, g)
    }

    /// `q`, a spot on the ground, moved along the ground until a leg with
    /// its hip at `hip` holds it within its working span: brought in toward
    /// the ground under the hip if it is too far, put out away from it if it
    /// is too close — as near as that goes, if it cannot be.
    private func refReach(_ q: V2, hip: V2, _ g: RefLeg) -> V2 {
        let d = q.distance(to: hip)
        let toward: V2
        let tooFar = d > g.hi
        if tooFar {
            toward = groundFoot(V2(hip.x, q.y))
        } else if d < g.lo {
            toward = groundFoot(V2(q.x + g.out * g.len, q.y))
        } else {
            return q
        }
        func ok(_ p: V2) -> Bool { tooFar ? p.distance(to: hip) <= g.hi : p.distance(to: hip) >= g.lo }
        guard ok(toward) else {
            // (Nowhere along there will do: whichever is the nearer miss.)
            let better = tooFar ? toward.distance(to: hip) < d : toward.distance(to: hip) > d
            return better ? toward : q
        }
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<10 {
            let m = (lo + hi) / 2
            if ok(groundFoot(V2.lerp(q, toward, m))) { hi = m } else { lo = m }
        }
        return groundFoot(V2.lerp(q, toward, hi))
    }

    /// The way out from the ground nearest `p`, in sprite space.
    private func refNormal(_ p: V2) -> V2 {
        guard mode == .attached, let loop = map.loop(anchor.loopID), !loop.edge.isEmpty else { return V2(0, 1) }
        let w = toWorld(p)
        var best = (d: CGFloat.greatestFiniteMagnitude, at: w, n: V2(0, 1))
        for e in loop.edge where e.len > 0.5 {
            let (t, d) = projectOnSegment(w, e.a, e.b)
            if d < best.d { best = (d, e.point(at: t), e.dir.perp) }
        }
        if let c = loop.onRoundedCorner(best.at) { best.n = c.normal }
        return toLocalDir(best.n)
    }

    /// How far out from the edge it is walking `p` (sprite units) is — less
    /// than 0 inside the thing — and which way out is, in the world.
    private func refOut(_ p: V2) -> (out: CGFloat, at: V2, dir: V2, corner: Bool)? {
        guard mode == .attached, let loop = map.loop(anchor.loopID), !loop.edge.isEmpty else { return nil }
        let w = toWorld(p)
        var best: (d: CGFloat, at: V2, n: V2, end: Bool)?
        for e in loop.edge where e.len > 0.5 {
            let (t, d) = projectOnSegment(w, e.a, e.b)
            guard best == nil || d < best!.d else { continue }
            best = (d, e.point(at: t), e.dir.perp, t < 0.01 || t > e.len - 0.01)
        }
        guard var b = best else { return nil }
        // (Round a window's corner the edge is the curve: out in the corner
        // of its square outline there is only air.)
        if loop.kind == .windowEdge, loop.cornerRadius > 0.5, loop.closed, b.end || loop.onRoundedCorner(b.at) != nil {
            let d = surfaceSide(w, loop), e: CGFloat = 0.25
            let g = V2(surfaceSide(w + V2(e, 0), loop) - surfaceSide(w - V2(e, 0), loop),
                       surfaceSide(w + V2(0, e), loop) - surfaceSide(w - V2(0, e), loop))
            let n = g.length > 1e-6 ? g.normalized : b.n
            return (d, w - n * d, n, false)
        }
        if b.end {
            // At a corner: out is the way both edges meeting there face.
            var n = V2.zero
            for e in loop.edge where e.len > 0.5 && (e.a.distance(to: b.at) < 0.5 || e.b.distance(to: b.at) < 0.5) { n += e.dir.perp }
            if n.length > 0.01 { b.n = n.normalized }
            let r = w - b.at
            return (r.dot(b.n) > 0 ? r.length : -r.length, b.at, b.n, true)
        }
        return ((w - b.at).dot(b.n), b.at, b.n, false)
    }

    /// `p` (sprite units) kept at least `clearance` out from the edge it is
    /// walking: a foot going round the outside of a corner goes over it,
    /// never through the thing.
    private func refClear(_ p: V2, by clearance: CGFloat) -> V2 {
        let c = clearance * max(config.scale, 0.05)
        guard let o = refOut(p), o.out < c else { return p }
        if o.corner {
            let r = toWorld(p) - o.at
            return o.out > 0 && r.length > 0.001 ? toLocal(o.at + r.normalized * c) : toLocal(o.at + o.dir * c)
        }
        return toLocal(toWorld(p) + o.dir * (c - o.out))
    }

    /// `p` kept within what leg `g`'s knee allows: never folded tighter, or
    /// held straighter, than `refFoldMost` and `refOpenMost`.
    private func refKeep(_ p: V2, _ g: RefLeg, giving give: CGFloat) -> V2 {
        let v = p - g.hip
        let d = v.length
        guard d > 0.001 else { return g.hip + V2(g.out * 0.3, -1).normalized * g.least }
        if d < g.least { return g.hip + v * (g.least / d) }
        let most = g.most(giving: give)
        if d > most { return g.hip + v * (most / d) }
        return p
    }

    /// A step's lift, `u` of the way through it: up briskly, highest a
    /// little before half way, and down gently — off the ground and back
    /// onto it at rest.
    private static func refLift(_ u: CGFloat) -> CGFloat {
        let x = clamp(u, 0, 1)
        let s = sin((x + 0.3 * x * (1 - x)) * .pi)
        return s * s
    }

    /// How far on its way a step is, `u` of the way through it: off from
    /// rest and on to rest, smoothly enough that neither end is a jolt.
    private static func refEase(_ u: CGFloat) -> CGFloat {
        let x = clamp(u, 0, 1)
        return x * x * x * (x * (6 * x - 15) + 10)
    }

    /// A leg's pose by its joints: the angle its thigh leaves the hip at, in
    /// sprite space, and the angle inside its knee.
    private struct RefJoints {
        var thigh: CGFloat
        var knee: CGFloat
    }

    /// Leg `g`'s joints with its foot at `foot`, its bones giving `give`.
    private static func refJoints(_ g: RefLeg, foot: V2, give: CGFloat) -> RefJoints {
        let a = g.thigh * give, b = g.shin * give
        let k = twoBoneKnee(hip: g.hip, foot: foot, thigh: a, shin: b, side: g.side)
        let d = clamp(foot.distance(to: g.hip), abs(a - b) + 0.01, a + b - 0.01)
        return RefJoints(thigh: (k - g.hip).angle, knee: acos(clamp((a * a + b * b - d * d) / (2 * a * b), -1, 1)))
    }

    /// Where leg `g`'s foot is with its joints at `j`, its bones giving `give`.
    private static func refFoot(_ g: RefLeg, _ j: RefJoints, give: CGFloat) -> V2 {
        let knee = g.hip + V2.angle(j.thigh) * (g.thigh * give)
        return knee + V2.angle(j.thigh - g.side * (.pi - j.knee)) * (g.shin * give)
    }

    /// How far through a step its foot is at its highest.
    private static let refPeak: CGFloat = 0.43

    /// A step of leg `g` from `a` to `b` (sprite units, both on the ground),
    /// `u` of the way through it. The leg moves as a leg does — by turning
    /// at its hip and its knee, both smoothly — from how it stood at `a`,
    /// up through its highest point, to how it will stand at `b`: so the
    /// knee travels in an easy arc however quickly the foot goes, and the
    /// foot leaves the ground and comes back to it at rest. The highest
    /// point is `height` over the way between the two, the foot drawn in a
    /// little toward the hip as the knee comes up — round the hip rather
    /// than folded up tight under it, and over the edge of whatever it is
    /// walking round, never through it.
    private func refStepPath(_ g: RefLeg, k: Int, from a: V2, to b: V2, u: CGFloat, height: CGFloat) -> (foot: V2, lift: CGFloat, give: CGFloat) {
        let lift = Spider.refLift(u)
        let e = Spider.refEase(u)
        let giveA = g.give(at: a), giveB = g.give(at: b)
        let give = lerp(giveA, giveB, e)
        // (A short step is a low one.)
        let h = height * clamp(a.distance(to: b) / 16 + 0.25, 0.45, 1.15)
        // The top of the step.
        let ep = Spider.refEase(Spider.refPeak)
        var top = V2.lerp(a, b, ep) + V2.lerp(refNormal(a), refNormal(b), ep).normalized * h
        top += (g.hip - top) * Spider.refDraw[k]
        let v = top - g.hip
        let d = v.length
        let w = max(g.len * 0.06, 1.5)
        if d < g.lo + w, d > 0.001 { top = g.hip + v * ((g.lo + w * exp((d - g.lo - w) / w)) / d) }
        top = refClear(top, by: h * 0.55)
        // The foot's way as a plain arc: from one spot to the other, up to
        // the top and down again.
        let up = V2.lerp(refNormal(a), refNormal(b), e).normalized
        var arc = V2.lerp(a, b, e) + up * (lift * h)
        arc += (g.hip - arc) * (Spider.refDraw[k] * sin(.pi * e) * sin(.pi * e))
        // (Passing under its own hip, it keeps below it by as much as the
        // leg's fold needs — lifted less there, not pushed out to one side,
        // which would throw it from one side of the hip to the other.)
        let rel = arc - g.hip
        let across = rel.dot(up.perp), rise = rel.dot(up)
        let room = g.lo + w * 0.5
        if rise < 0, abs(across) < room {
            let deep = (room * room - across * across).squareRoot()
            if -rise < deep { arc = g.hip + up.perp * across - up * deep }
        } else if rise >= 0, rel.length < room, rel.length > 0.001 {
            arc = g.hip + rel * (room / rel.length)
        }
        // And as the leg moves: its joints through the three — a curve in
        // joint space that leaves the first, passes through the top and
        // arrives at the last (each angle taken the short way round from the
        // one before) — so the knee goes in an easy arc however quickly the
        // foot goes.
        let j0 = Spider.refJoints(g, foot: a, give: giveA)
        let j1 = Spider.refJoints(g, foot: b, give: giveB)
        let jt = Spider.refJoints(g, foot: top, give: lerp(giveA, giveB, ep))
        func through(_ x0: CGFloat, _ xt: CGFloat, _ x1: CGFloat) -> CGFloat {
            let c = (xt - (1 - ep) * (1 - ep) * x0 - ep * ep * x1) / (2 * ep * (1 - ep))
            return (1 - e) * (1 - e) * x0 + 2 * e * (1 - e) * c + e * e * x1
        }
        let tTop = j0.thigh + angleDelta(j0.thigh, jt.thigh)
        let tEnd = tTop + angleDelta(tTop, j1.thigh)
        let thigh = through(j0.thigh, tTop, tEnd)
        let knee = clamp(through(j0.knee, jt.knee, j1.knee), Spider.refFoldMost, Spider.refOpenMost)
        let joint = Spider.refFoot(g, RefJoints(thigh: thigh, knee: knee), give: give)
        // A step the leg would have to swing right round for goes as the
        // plain arc instead, by degrees: the joint curve for any ordinary
        // step, however folded the leg. (The second pair — a short thigh on
        // a long shin, its foot coming up from under its hip — swing round
        // a long way even walking along a ledge, and go by the arc sooner.)
        let sweep = max(abs(tTop - j0.thigh), abs(tEnd - tTop), abs(tEnd - j0.thigh))
        let plain = smoothstep((sweep - (k == 1 ? 1.2 : 2.4)) / 0.6)
        var p = V2.lerp(joint, arc, plain)
        p = refClear(p, by: lift * h * 0.3)
        return (refKeep(p, g, giving: give), lift, give)
    }

    /// The nearest point of the ground to `p` (sprite units), and how far
    /// off it `p` is. `groundFoot`, but on a window's rounded corner truly
    /// the nearest point of the curve — so a foot standing on the curve is
    /// left exactly where it is, rather than crept along it frame by frame.
    private func refGroundNear(_ p: V2) -> (point: V2, dist: CGFloat) {
        let g = groundFoot(p)
        if let loop = map.loop(anchor.loopID), loop.cornerRadius > 0.5, let c = loop.onRoundedCorner(toWorld(g)) {
            let centre = c.point - c.normal * loop.cornerRadius
            let w = toWorld(p)
            let v = w - centre
            if v.length > 0.001 {
                let q = toLocal(centre + v * (loop.cornerRadius / v.length))
                return (q, p.distance(to: q))
            }
        }
        return (g, p.distance(to: g))
    }

    /// Sets leg `leg` off on a step of its own, out of turn, to `target`.
    private func refBeginStep(_ leg: inout Leg, to target: V2, dur: CGFloat) {
        leg.settle = 0
        leg.swingFrom = leg.foot
        leg.settleTo = target
        leg.stepDur = max(dur, 0.08)
        leg.swinging = false
    }

    /// On through a step of its own (see `refBeginStep`), its ends held
    /// where they are on the ground while the body moves (`delta`, its
    /// motion over them this frame, and `dTheta`, its turn).
    private func refStep(_ leg: inout Leg, _ i: Int, _ g: RefLeg, k: Int, height: CGFloat, delta: V2, dTheta: CGFloat, dt: CGFloat) {
        leg.swingFrom = leg.swingFrom.rotated(by: -dTheta) - delta
        leg.settleTo = leg.settleTo.rotated(by: -dTheta) - delta
        leg.settle = min(1, leg.settle + dt / max(leg.stepDur, 0.05))
        let (foot, lift, give) = refStepPath(g, k: k, from: leg.swingFrom, to: leg.settleTo, u: leg.settle, height: height)
        leg.foot = foot
        leg.lift = lift
        refGiveNow[i] = give
        if leg.settle >= 1 {
            leg.foot = leg.settleTo
            leg.settle = -1
            leg.stepDur = 0
            leg.lift = 0
            leg.landedAt = t
        }
    }

    /// Whether leg `i` may step now, out of turn: not with too many feet up
    /// already, nor — unless it must — while a neighbour on its side is up.
    private func refMayStep(_ i: Int, urgent: Bool) -> Bool {
        let up = legs.indices.filter { $0 != i && (legs[$0].swinging || legs[$0].settle >= 0) }
        if up.count >= (urgent ? 5 : 3) { return false }
        return urgent || !up.contains { ($0 < 4) == (i < 4) && abs($0 % 4 - i % 4) == 1 }
    }

    private func updateRefinedGait(dt: CGFloat, profile: CGFloat, m: CGFloat, dTheta: CGFloat, deltaLocal: V2, overFeet: V2, ownSteps: Bool) {
        let scale = max(config.scale, 0.05)
        let walking = speed > 1
        let fwd: CGFloat = walkDir * m < 0 ? -1 : 1
        refStill = walking ? 0 : refStill + dt

        // The rhythm, by the pace it means to go (kept through a pause):
        // dawdling, more of each step on the ground and the steps rippling
        // further apart; hurrying, more of it in the air.
        let pace = (targetSpeed > 1 ? targetSpeed : speed) / scale
        let slow = clamp((44 - pace) / 20, 0, 1), quick = clamp((pace - 75) / 110, 0, 1)
        refSwing = approach(refSwing, lerp(lerp(0.38, 0.27, slow), 0.46, quick), 1.5, dt)
        refRipple = approach(refRipple, lerp(lerp(0.05, 0.11, slow), 0.03, quick), 1.0, dt)
        let swing = refSwing

        // What each leg can reach from where its hip is, over the line the
        // body stands over; the stance all eight can take; and the middle
        // of each leg's stance — where it stands still, or as near that as
        // leaves room for the whole stance within reach.
        let ground = SpiderRenderer.ground - refRide / scale
        var geo = legs.indices.map { refLeg($0, profile: profile, ground: ground) }
        refSweep = max((geo.map { $0.to - $0.from }.min() ?? 20) * 0.92, 6)
        let stride = strideNow
        let half = min(stride * (1 - swing), refSweep) / 2
        for i in geo.indices {
            let g = geo[i]
            let c = g.from + half <= g.to - half ? clamp(g.rest.x, g.from + half, g.to - half) : (g.from + g.to) / 2
            geo[i].centre = c
            geo[i].midSpan = max(V2(c, ground).distance(to: g.hip), 1)
            geo[i].walkSpan = max(V2(c - half, ground).distance(to: g.hip), V2(c + half, ground).distance(to: g.hip))
        }

        // How far the gait clock goes on in a frame, and how long a step takes.
        let phStep = speed / (stride * scale) * dt
        let stepTime = phStep > 0.0001 ? clamp(swing * dt / phStep, 0.1, Spider.refLongestStep) : Spider.refLongestStep
        let v = speed / scale
        let now = refPath(ahead: 0)
        let style: CGFloat = gaitStyle == .bouncy ? 1.4 : (gaitStyle == .tiptoe ? 1.3 : (gaitStyle == .lumber ? 0.75 : 1))
        let careful: CGFloat = activity == .sneak ? 1.35 : 1
        let lively = style * careful * (1 - 0.3 * quick) * clamp(stepTime / 0.16, 0.6, 1)

        for i in legs.indices {
            var leg = legs[i]
            let g = geo[i], k = i % 4
            leg.footVel = .zero
            let height = Spider.refHeight[k] * lively
            var ph = (gaitPhase - refStart(i)).truncatingRemainder(dividingBy: 1)
            if ph < 0 { ph += 1 }
            if leg.swingShift != 0, leg.swinging, ph > 0.75 { ph -= 1 }
            let swingEnd = swing + leg.swingShift

            if ph >= swingEnd { leg.skipSwing = false }
            // A leg whose turn is already well on as it starts walking — or
            // that has only just stepped, out of turn — sits this one out.
            if walking, ph < swingEnd, !leg.swinging, leg.settle < 0, ph > swing * 0.3 || t - leg.landedAt < 0.2 {
                leg.skipSwing = true
            }
            if walking, ph < swingEnd, !leg.skipSwing, leg.settle < 0 {
                // A step in its turn, timed to be down on the last frame of
                // its window — and never slower than any step takes.
                if !leg.swinging {
                    leg.swingPh0 = ph
                    leg.swingU = 0
                }
                let last = max(swingEnd - phStep, leg.swingPh0 + 0.01)
                let ahead = min(max(last - ph, 0) * stride, (1 - leg.swingU) * Spider.refLongestStep * v)
                let target = refTarget(i, g, ahead: ahead, half: half, fwd: leg.swinging ? leg.swingDir : fwd, ground: ground, now: now)
                if !leg.swinging {
                    leg.swinging = true
                    leg.swingFrom = leg.foot
                    leg.swingDir = fwd
                    leg.swingTo = target
                } else {
                    if !ownSteps { leg.swingDir = fwd }
                    // The step runs over the ground: it leaves from the spot
                    // the foot stood on and goes to a spot on the ground, both
                    // staying where they are while the body goes on.
                    leg.swingFrom = leg.swingFrom.rotated(by: -dTheta) - deltaLocal
                    leg.swingTo = leg.swingTo.rotated(by: -dTheta) - deltaLocal
                    // (Following where it means to land as that moves — the
                    // pace changing — but only so fast, and not as it comes
                    // down: a foot in the air never whips round after a spot
                    // that has jumped, round a corner, from one wall to the next.)
                    if leg.swingU < 0.6 {
                        let shift = (target - leg.swingTo) * (1 - exp(-dt * 16))
                        leg.swingTo += shift.clampedLength(60 * dt)
                    }
                }
                let byClock = clamp((ph - leg.swingPh0) / (last - leg.swingPh0), 0, 1)
                leg.swingU = min(1, max(leg.swingU + dt / Spider.refLongestStep, byClock))
                let (foot, lift, give) = refStepPath(g, k: k, from: leg.swingFrom, to: leg.swingTo, u: leg.swingU, height: height)
                leg.foot = foot
                leg.lift = lift
                refGiveNow[i] = give
                if leg.swingU >= 1 {
                    leg.foot = leg.swingTo
                    leg.lift = 0
                    leg.swinging = false
                    leg.skipSwing = true
                    leg.landedAt = t
                }
            } else if leg.settle >= 0 {
                leg.swinging = false
                if leg.stepDur > 0 {
                    refStep(&leg, i, g, k: k, height: height, delta: walking ? deltaLocal : overFeet, dTheta: dTheta, dt: dt)
                } else {
                    // (A settling step something else began: on as it was going.)
                    _ = settleFoot(&leg, i, to: leg.settleTo, dt: dt)
                }
            } else {
                leg.swinging = false
                leg.swingShift = 0
                leg.lift = approach(leg.lift, 0, 16, dt)
                if walking {
                    // Stance: held where it stands on the ground while the
                    // body goes on over it.
                    leg.foot = leg.foot.rotated(by: -dTheta) - deltaLocal
                    let under = refGroundNear(leg.foot)
                    let inAir = under.dist > 4
                    if under.dist > 0.75 {
                        leg.foot = under.dist > 2 ? approach(leg.foot, under.point, 14, maxSpeed: 240, dt) : under.point
                    }
                    // Left further out than a stride along a ledge ever takes
                    // it — the body coming round a corner over it, the pace
                    // picking up — or left behind its stance, or still up in
                    // the air from whatever went before: it steps on now, out
                    // of turn, rather than the leg stretching to keep it. It
                    // would rather; near as far as the leg goes, it must — and
                    // must, too, once carried round behind its own hip, where
                    // its knee would have to bend the wrong way.
                    let past = fwd > 0 ? g.from - leg.foot.x : leg.foot.x - g.to
                    let d = leg.foot.distance(to: g.hip)
                    let urgent = d > g.hi * 0.98 || d < g.least * 1.1 || inAir || past > 2
                    let behind = fwd * (leg.foot.x - g.centre) < -(half + 3) || past > 0
                    if urgent || behind || d > g.walkSpan * 1.04 + 0.5 || d < g.lo, refMayStep(i, urgent: urgent) {
                        let target = refTarget(i, g, ahead: stepTime * v, half: half, fwd: fwd, ground: ground, now: now)
                        refBeginStep(&leg, to: target, dur: stepTime)
                        refStep(&leg, i, g, k: k, height: height, delta: .zero, dTheta: 0, dt: dt)
                    }
                } else if absorbingLanding || watchingPlanted && !Spider.onFoot.contains(activity) {
                    standStill(&leg, i, profile: profile, dTheta: dTheta, overFeet: overFeet, dt: dt)
                } else {
                    refTidy(&leg, i, g, k: k, height: height, profile: profile, dTheta: dTheta, overFeet: overFeet, dt: dt)
                }
            }
            // Standing on it, the leg gives as far out as its foot is — which
            // changes only as the body moves over it. (Never quickly: a foot
            // some other step has moved catches up over a few frames.)
            if !leg.swinging, !(leg.settle >= 0 && leg.stepDur > 0) {
                refGiveNow[i] += clamp(g.give(at: leg.foot) - refGiveNow[i], -1.2 * dt, 1.2 * dt)
            }
            legs[i] = leg
        }
    }

    /// Standing, walking the refined way: every foot stays where it is on
    /// the ground, and one left well off its spot — the walk stopped
    /// mid-stride — takes a small step there, two legs at a time at most
    /// and never two neighbours together, rather than sliding over. Just
    /// stopped, a foot only a little off is left be: it stands as it walked.
    private func refTidy(_ leg: inout Leg, _ i: Int, _ g: RefLeg, k: Int, height: CGFloat, profile: CGFloat, dTheta: CGFloat, overFeet: V2, dt: CGFloat) {
        var rest = SpiderRenderer.rig(i, profile: profile, look: look).foot
        rest.x += leg.wobble.value(t * 0.8) * 0.5
        let target = refReach(reachableSpot(rest, spread: true, leg: i).point, hip: g.hip, g)
        leg.foot = leg.foot.rotated(by: -dTheta) - overFeet
        let under = refGroundNear(leg.foot)
        let inAir = under.dist > 2
        let off = leg.foot.distance(to: target)
        let slack: CGFloat = refStill > 0.8 ? 2.5 : 5
        let busy = legs.indices.filter { $0 != i && (legs[$0].settle >= 0 || legs[$0].swinging) }
        let neighbour = busy.contains { ($0 < 4) == (i < 4) && abs($0 % 4 - i % 4) == 1 }
        if off > slack, inAir || off > 14 || (busy.count < 2 && !neighbour) {
            refBeginStep(&leg, to: target, dur: 0.24)
            refStep(&leg, i, g, k: k, height: height, delta: .zero, dTheta: 0, dt: dt)
        } else if under.dist > 0.75 {
            leg.foot = inAir ? approach(leg.foot, under.point, 14, maxSpeed: 240, dt) : under.point
        }
    }

    // MARK: - On a line

    /// Where each leg takes hold of the line climbing, in sprite units along
    /// the body: the front pairs reaching up it past the head, the hind
    /// pairs down it past the abdomen — spread along it, so they each have
    /// a stretch of it to themselves.
    private static let lineClimb: [CGFloat] = [40, 29, -22, -36, 36, 27, -25, -34]

    /// How the body sits on the line, turned from lying along it: hanging
    /// head down, a touch belly up toward the silk its hind legs hold;
    /// climbing, leaning back a little off it from the abdomen up, as it
    /// hangs from its front legs with its weight under them.
    private var lineTilt: CGFloat { hangHeadUp ? facing * Spider.climbLean : -facing * 0.1 }
    private static let climbLean: CGFloat = 0.1
    /// Turning end for end, how far ahead of the body its heading's spring
    /// is led round, radians: what sets how fast it rolls over.
    private static let turnLead: CGFloat = 1.0

    /// Where each hind leg holds the line hanging head down, in sprite units
    /// along it above the spinnerets: the third pair out to the side and in
    /// to the silk just over the tip of the abdomen, the fourth reaching up
    /// along the abdomen to hold it higher. The front pairs hang free.
    private static let lineHang: [CGFloat?] = [nil, nil, 4, 16, nil, nil, 2, 12]
    /// Rolling over end for end about its middle, where each hind foot
    /// keeps the silk in against the belly, in sprite units along the body:
    /// the fourth pair at the tip of the abdomen, where it comes out of
    /// the spinnerets, the third pair half-way along.
    private static let lineTuck: [CGFloat] = [0, 0, -17, -27, 0, 0, -19, -29]
    /// How far the body goes along the line per cycle of the climbing gait,
    /// in sprite units, and the share of it each foot spends reaching on.
    private static let lineStride: CGFloat = 28
    private static let lineDuty: CGFloat = 0.34

    /// How much of the line, in sprite units from where it meets the body,
    /// is drawn in the sprite (see `SpiderPose.thread`): hanging, past the
    /// hind feet holding it over the spinnerets; climbing, past the front
    /// feet up over the head. The world's line takes over beyond.
    private var heldStretch: CGFloat { lerp(28, 110, climbLayout) }

    /// Whose proportions a leg is drawn with hanging on a line. Standing,
    /// the near legs splay out toward you and are seen foreshortened; held
    /// along the body — reaching up the silk, or hanging straight down — a
    /// leg is seen its whole length, which is its far twin's.
    private static func lineBones(_ i: Int) -> Int { i < 4 ? i + 4 : i }

    /// How far leg `i` reaches hanging on a line, hip to foot, in sprite units.
    private func lineReach(_ i: Int) -> CGFloat {
        let r = SpiderRenderer.rig(Spider.lineBones(i), profile: 1, look: look)
        return (r.knee - r.hip).length + (r.foot - r.knee).length
    }

    /// The line where it leaves the body, in sprite space, toward the
    /// anchor: along the silk as it really lies there, `reach` sprite units
    /// out — a line that is swinging or paying out bows a little — so the
    /// feet holding it, and the stretch drawn over it, sit right on it.
    private func threadDirection(reach: CGFloat) -> V2 {
        let spin = silkAttachWorld()
        var toward = webAnchor
        if rope.live {
            for p in rope.points.reversed() where p.distance(to: spin) >= reach * config.scale {
                toward = p
                break
            }
        }
        let d = toLocalDir(toward - spin)
        return d.length > 0.001 ? d.normalized : V2(-1, 0)
    }

    /// A foot on the line, `at` units along it from `origin`, its pad on
    /// the flank of the line facing the leg — pulled back along the line to
    /// the nearest spot the leg can really reach, never stretched past it.
    /// Where, and how far along that is.
    private func grip(on origin: V2, dir: V2, at: CGFloat, side: V2, hip: V2, reach: CGFloat) -> (V2, CGFloat) {
        let base = origin + side * 1.6
        // Points on the line, as seen from the hip: p + dir * s.
        let p = base - hip
        let mid = -p.dot(dir)
        let r = reach * 0.97
        let disc = r * r - (p.lengthSquared - mid * mid)
        var s = at
        if disc <= 0 {
            s = mid                                   // out of reach: the nearest point
        } else {
            let half = disc.squareRoot()
            s = clamp(at, mid - half, mid + half)
        }
        return (base + dir * s, s)
    }

    /// Where a foot takes hold of the line running out from `origin` along
    /// `dir`: as near `at` along it as the leg comfortably reaches from
    /// `hip` (`reach`), never back past `origin`; with the line not yet in
    /// its reach, as far toward it as the leg goes.
    private func reachOnLine(from origin: V2, dir: V2, at: CGFloat, hip: V2, reach: CGFloat) -> V2 {
        let p = origin - hip
        let mid = -p.dot(dir)
        let disc = reach * reach - (p.lengthSquared - mid * mid)
        var s = mid
        if disc > 0 {
            let half = disc.squareRoot()
            s = clamp(at, mid - half, mid + half)
        }
        let f = origin + dir * max(s, 0)
        let off = f - hip
        return off.length > reach ? hip + off.normalized * reach : f
    }

    /// Onto a line: the legs take it up from wherever they were.
    private func startLineLegs() {
        freeFoot = legs.map { toWorld($0.foot) }
        // (Going as the body carries them: along with it, and round with it.)
        freeFootVel = freeFoot.map { vel + ($0 - pos).perp * bodySpin }
        let spin = lineStance
        let dir = threadDirection(reach: heldStretch)
        for i in legs.indices {
            lineS[i] = (legs[i].foot - spin).dot(dir)
            legs[i].swinging = false
        }
        regripLeg = -1
        lineAligned = Spider.alignment(dir)
        lineAlignedVel = 0
        frontHoldsWas = climbLayout
        lineHoldWas = legs.indices.map { Spider.lineHang[$0] != nil ? 1 : climbLayout }
        gripTurn = Array(repeating: nil, count: legs.count)
    }

    /// How nearly the body lies along the line, by the silk where it meets
    /// the belly, 0…1. (The anchor as seen from the body's middle, off to
    /// the side of the line, is further round.)
    private static func alignment(_ dir: V2) -> CGFloat {
        smoothstep(clamp((dir.x - 0.9) / 0.07, 0, 1))
    }
    /// Climbing, how far the feet hold the silk itself rather than going
    /// with the body (see `updateLineLegs`), and how fast that is changing.
    private var lineAligned: CGFloat = 0
    private var lineAlignedVel: CGFloat = 0
    /// How much the front legs had hold of the line last frame, and each
    /// leg of its own.
    private var frontHoldsWas: CGFloat = 0
    private var lineHoldWas: [CGFloat] = []
    /// Rolling over to climb, how far each front foot has got reaching for
    /// the line, 0…1.
    private var lineCatch: [CGFloat] = []
    /// Taking hold of the line or letting go, the way each foot is going
    /// round its hip (see `roundHip`).
    private var holdTurn: [CGFloat?] = []

    /// The legs on a line. Hanging head down, the hind two pairs hold the
    /// silk just above the spinnerets — feeding it out between them, a
    /// stroke at a time, as it goes down — and the front two pairs hang
    /// free under their own weight, swinging with the body; swinging on the
    /// line, they kick with it to pump it up. To climb, it rolls over head
    /// up about its middle: the hind pairs draw the silk in against its
    /// belly and keep it there, the front pairs fold in and reach up for the
    /// line as it comes round. Climbing, it hugs the line: the silk runs
    /// along its belly, against the abdomen, the front pairs reaching up it
    /// and the hind pairs down it, and it goes up it hand over hand —
    /// through its stance a foot keeps its hold on the silk while the body
    /// goes past it, then lets go, lifts off and reaches on up for the next
    /// hold.
    private func updateLineLegs(dt: CGFloat) {
        let sc = max(config.scale, 0.05)
        // Where the line leaves the body as it hangs or climbs, which the
        // feet hold it from; and, turning end for end, the middle it is
        // drawn in to and turned about (see `lineGrip`).
        let spin = lineStance
        let pivot = turnPivot
        let gripW = smoothstep(lineGrip)
        let up = upness
        let climbing = climbLayout
        let dir = threadDirection(reach: heldStretch)
        lineDirLocal = dir
        // Travel along the line this frame, sprite units, + = toward the anchor.
        let toward = -hangDelta / sc
        let hauling = toward > 0.001
        let feeding = toward < -0.001 && up < 0.5
        let stride = Spider.lineStride, duty = Spider.lineDuty
        let stroke = stride * (1 - duty)
        if hauling { climbPhase += toward / stride }
        if feeding { feedPhase += dt * clamp(-toward / max(dt, 0.001) / 30, 0.8, 2.2) }
        // Hanging still, a hind foot shifts its hold now and then.
        if !hauling, !feeding, up < 0.2, webStyle == .hang, lineGrip <= 0, regripLeg < 0 {
            regripIn -= dt
            if regripIn <= 0 {
                regripLeg = [2, 3, 6, 7].randomElement() ?? 3
                regripT = 0
                regripIn = randRange(2.5, 6)
            }
        }
        if regripLeg >= 0 {
            regripT += dt / 0.3
            if regripT >= 1 || hauling || feeding { regripLeg = -1 }
        }
        // Hanging free, a leg goes down in the world, and out to the side
        // the legs are on.
        let g = toLocalDir(V2(0, -1))
        var out = V2(0, -1) - g * g.dot(V2(0, -1))
        out = out.length > 0.2 ? out.normalized : V2(g.y, -g.x)
        // Holding the line hanging, a knee bends out on the belly side of it
        // — the side the legs are on — and a foot letting go lifts off it
        // that way. (Half-way round end for end the line runs off the belly
        // itself: then it is whichever side the hip is.)
        let belly = V2(0, -1) - dir * dir.dot(V2(0, -1))
        // Climbing, the feet hold the silk once the body lies along it; the
        // body swinging round off it, they go with the body — going over
        // from one to the other on a spring, however fast it swings round,
        // since a foot far up the line has a long way to go: quickly onto
        // the silk as the body comes into line, gently off it.
        let alignNow = Spider.alignment(dir)
        let (ak, ac): (CGFloat, CGFloat) = alignNow > lineAligned ? (625, 50) : (100, 20)
        lineAlignedVel += ((alignNow - lineAligned) * ak - lineAlignedVel * ac) * dt
        lineAligned = clamp(lineAligned + lineAlignedVel * dt, 0, 1)
        let aligned = lineAligned
        // The front legs take hold of the line as the body comes round to
        // climb; setting off back round to hang, they let go of it as the
        // body starts round and fall away free, as it rolls back over
        // about its middle.
        let frontHolds: CGFloat = hangHeadUp ? climbing : (climbing >= 1 && alignNow >= 1 ? 1 : 0)
        frontHoldsWas = frontHolds
        if lineHoldWas.count != legs.count { lineHoldWas = Array(repeating: 1, count: legs.count) }
        if gripTurn.count != legs.count { gripTurn = Array(repeating: nil, count: legs.count) }
        // How far up the line it is fastened, from where the climbing
        // stance meets it.
        let lineTopS = (toLocal(webAnchor) - climbHold).length
        // Pumping a swing, the free legs kick with it, reaching the way it
        // is going.
        let kick = webStyle == .swing && swingPumping ? clamp(swingVel.x / (360 * sc), -1, 1) * 0.8 : 0

        for i in legs.indices {
            var leg = legs[i]
            leg.settle = -1
            leg.footVel = .zero
            let hip = leg.hip
            let reach = lineReach(i)
            var side = belly
            if side.length < 0.35 {
                let rel = hip - spin
                side = rel - dir * rel.dot(dir)
            }
            side = side.length > 0.01 ? side.normalized : out
            // Where it takes hold climbing, along the silk.
            let climbAt = Spider.lineClimb[i] - climbHold.x
            let hangAt = Spider.lineHang[i]
            // How much it has hold of the line: the hind pairs always, the
            // front pairs once it has come round head up to climb — rolling
            // over to climb, as the line comes round within their reach,
            // the second pair a moment before the first. (Letting go part
            // way round, a foot falls from where it is.)
            var holds: CGFloat = hangAt != nil ? 1 : frontHolds
            if hangAt == nil {
                // (A reach that takes the leg its own time, however fast
                // the body is coming round.)
                if lineCatch.count != legs.count { lineCatch = Array(repeating: 0, count: legs.count) }
                let from: CGFloat = i % 4 == 1 ? 0.1 : 0.16
                if hangHeadUp, gripW > 0 {
                    if up > from { lineCatch[i] = min(1, lineCatch[i] + dt / 0.4) }
                } else {
                    lineCatch[i] = 0
                }
                holds = max(holds, smoothstep(lineCatch[i]) * gripW)
            }
            let dropping = holds <= 0 && lineHoldWas[i] > 0 && lineHoldWas[i] < 1
            lineHoldWas[i] = holds

            var held = leg.foot
            if holds > 0 {
                let centre = lerp(hangAt ?? climbAt, climbAt, climbing)
                let hi = centre + stroke / 2
                // Hauling in: head up every leg climbs; head down — a small
                // adjustment — the hind pairs do it. (Swinging, it just
                // holds on.)
                let gait = hauling && webStyle == .hang && (hangAt != nil || climbing > 0.9)
                var ph = (climbPhase + leg.phase).truncatingRemainder(dividingBy: 1)
                if ph < 0 { ph += 1 }
                if gait, ph < duty {
                    // Let go, and reach on up the line for the next hold —
                    // from where it held the silk to the spot on it that
                    // will be at the top of its stroke as it takes hold, so
                    // it leaves and arrives at rest on the silk, as a foot
                    // steps from ground to ground walking.
                    if !leg.swinging {
                        leg.swinging = true
                        leg.swingPh0 = min(ph, duty * 0.6)
                        lineSwingFrom[i] = lineS[i]
                    } else {
                        lineSwingFrom[i] -= toward
                    }
                    let u = clamp((ph - leg.swingPh0) / max(duty - leg.swingPh0, 0.01), 0, 1)
                    lineS[i] = lerp(lineSwingFrom[i], hi + (duty - ph) * stride, easeInOutSine(u))
                    leg.lift = pow(sin(u * .pi), 1.5)
                } else if gait {
                    // Holding on: its hold on the silk stays put while the
                    // body goes past it.
                    leg.swinging = false
                    lineS[i] -= toward
                    leg.lift = approach(leg.lift, 0, 20, dt)
                } else if feeding, i % 4 == 3 {
                    // Paying out: the hind feet take turns drawing silk from
                    // the spinnerets — up the line with it, then back down
                    // for more.
                    leg.swinging = false
                    var fp = (feedPhase + (i < 4 ? 0 : 0.5)).truncatingRemainder(dividingBy: 1)
                    if fp < 0 { fp += 1 }
                    let s0 = centre - 2.5, s1 = centre + 3.5
                    var want = lerp(s0, s1, fp / 0.7)
                    var lift: CGFloat = 0
                    if fp >= 0.7 {
                        let u = (fp - 0.7) / 0.3
                        want = lerp(s1, s0, easeInOutSine(u))
                        lift = sin(u * .pi) * 0.8
                    }
                    lineS[i] = approach(lineS[i], want, 30, dt)
                    leg.lift = approach(leg.lift, lift, 30, dt)
                } else {
                    // Holding still: settles onto its hold, with the odd
                    // shift. Coming round to climb, the feet take up their
                    // holds for it as the body comes round, ready to go;
                    // stopped part way up, each keeps the hold it has.
                    leg.swinging = false
                    var want = centre + leg.wobble.value(t * 0.5) * 0.7
                    var lift: CGFloat = 0
                    if regripLeg == i {
                        lift = sin(regripT * .pi) * 0.9
                        want += sin(regripT * .pi) * 3
                    }
                    leg.lift = approach(leg.lift, lift, 18, dt)
                    if climbing >= 1 {
                        // (Still holding it as the body moves along the
                        // line — paying out before it turns to go down.)
                        lineS[i] -= toward
                    } else {
                        lineS[i] = approach(lineS[i], want, climbing > 0 ? 30 : 7, dt)
                    }
                }
                // Hanging, the foot is where the leg can reach the silk;
                // climbing, it is on the silk along its belly. (The front
                // legs never hold it hanging: they go from hanging free
                // straight to their holds for climbing — not by way of
                // wherever the line happens to pass them as the body
                // swings round, which may be right by the hip.)
                var hang = held
                if climbing < 1, hangAt != nil {
                    let (p, s) = grip(on: spin, dir: dir, at: lineS[i], side: side, hip: hip, reach: reach)
                    if climbing <= 0 { lineS[i] = s }
                    hang = p + side * (leg.lift * 4.5)
                }
                var walk = held
                if climbing > 0 {
                    // Along its own stance line, which comes round onto the
                    // silk as the body does: turning, the feet go with the
                    // body rather than out to wherever the line is. A foot
                    // letting go lifts off it outward, away from the body.
                    lineS[i] = clamp(lineS[i], centre - stroke, centre + stroke)
                    // (Nearly at the top, a foot reaching up takes hold
                    // where the line is fastened, not past it.)
                    lineS[i] = min(lineS[i], max(lineTopS - 1.5, 0))
                    let along = (V2(1, 0) + (dir - V2(1, 0)) * aligned).normalized
                    let off = V2(along.y, -along.x)
                    walk = climbHold + along * lineS[i] + off * (leg.lift * 5)
                }
                held = hangAt != nil ? V2.lerp(hang, walk, climbing) : walk
                // Rolling over end for end about its middle: the hind feet
                // keep the silk in against the belly, where it runs from the
                // spinnerets in under the abdomen to its middle; the front
                // feet hold the line where it leaves its middle for the
                // anchor — as far up it, toward where they will hold it
                // climbing, as they comfortably reach.
                if gripW > 0 {
                    let turnAt = hangAt != nil ? bellyLine(Spider.lineTuck[i])
                        : reachOnLine(from: pivot, dir: dir, at: Spider.lineClimb[i] - pivot.x, hip: hip, reach: reach * 0.78)
                    if gripW >= 1 {
                        gripTurn[i] = nil
                        held = turnAt
                    } else {
                        held = Spider.roundHip(held, turnAt, hip: hip, gripW, turn: &gripTurn[i], fold: 0.2)
                    }
                } else {
                    gripTurn[i] = nil
                }
            } else {
                leg.swinging = false
                leg.lift = approach(leg.lift, 0, 10, dt)
                gripTurn[i] = nil
            }

            var free = held
            if dropping, hangAt == nil, freeFoot.count == legs.count {
                freeFoot[i] = toWorld(leg.foot)
                freeFootVel[i] = vel
            }
            if holds < 1 {
                // (Rolling over to climb, the front legs are drawn in, ready
                // to reach up for the line.)
                free = freeLegFoot(i, hip: hip, reach: reach, down: g, out: out, kick: kick,
                                   tuck: hangHeadUp ? gripW : 0, dt: dt)
                // Not holding on at all: ready to take hold nearest where it is.
                if holds <= 0 { lineS[i] = (free - spin).dot(dir) }
            } else if freeFoot.count == legs.count {
                // Holding on, its free self goes with the foot, ready to let
                // go from there, going as the foot was.
                let w = toWorld(held)
                let moving = dt > 0 ? (w - freeFoot[i]) / dt : vel
                freeFootVel[i] = vel + (moving - vel).clampedLength(600 * sc)
                freeFoot[i] = w
            }
            // Taking hold or letting go, the foot swings round between the
            // two at arm's length, rather than straight across through the
            // hip.
            if holdTurn.count != legs.count { holdTurn = Array(repeating: nil, count: legs.count) }
            if holds >= 1 || holds <= 0 {
                holdTurn[i] = nil
                leg.foot = holds >= 1 ? held : free
            } else {
                leg.foot = Spider.roundHip(free, held, hip: hip, holds, turn: &holdTurn[i], fold: 0.5)
            }
            // (Holding the line hanging, a fourth leg's knee is over the
            // abdomen it reaches up along; a third leg's is out to the side,
            // the line's. Climbing, the knees bend out from the silk.)
            let arch: CGFloat = i % 4 == 3 ? -1 : 1
            let hangBend = side * (holds * arch) + out * (1 - holds)
            let climbBend = V2(0, -1)
            var bend = hangBend * (1 - climbing) + climbBend * climbing
            // (Rolling over, as climbing: out from the silk it holds — for a
            // front foot up the line, square to the line, on the side it
            // bends to climbing, as the line comes round, so the knee never
            // has to go over from one side of the leg to the other.)
            if gripW > 0 {
                let holdBend = hangAt != nil ? climbBend : V2(dir.y, -dir.x)
                bend = bend * (1 - gripW) + (holdBend * holds + out * (1 - holds)) * gripW
            }
            legBend[i] = bend.length > 0.01 ? bend.normalized : side
            legBones[i] = Spider.lineBones(i)
            legs[i] = leg
        }
    }

    /// A leg hanging free on a line: its foot is a weight on the end of the
    /// limb, drawn toward where the leg holds it and swinging with the
    /// body's own motion — loosely, so it lags a touch behind whatever the
    /// body does and swings back through, though a live leg, not a limp
    /// one. It hangs down from the hip, knee a little bent, the four fanned
    /// out to its side of the body — the first pair furthest down, the
    /// second further out — each drifting on its own; going down, the first
    /// pair reach for whatever is below; pleased, they all paddle; pumping
    /// a swing, they kick with it (`kick`, a turn in the world); about to
    /// reach for something, drawn in (`tuck`, 0…1).
    private func freeLegFoot(_ i: Int, hip: V2, reach: CGFloat, down g: V2, out: V2, kick: CGFloat,
                             tuck: CGFloat = 0, dt: CGFloat) -> V2 {
        let sc = max(config.scale, 0.05)
        if freeFoot.count != legs.count {
            freeFoot = legs.map { toWorld($0.foot) }
            freeFootVel = Array(repeating: vel, count: legs.count)
        }
        let k = i % 4, near = i < 4
        // How far down and how far out the foot hangs, as shares of the leg.
        let (down, o): (CGFloat, CGFloat) = k == 0 ? (near ? (0.74, 0.2) : (0.8, -0.06)) : (near ? (0.6, 0.42) : (0.68, 0.22))
        let w = legs[i].wobble
        var d = down + w.value(t * 0.7 + 5) * 0.07
        if k == 0, hangDelta > 0.3 * sc { d = min(d + 0.07, 0.96) }
        var turn = w.value(t * 0.9 + CGFloat(i) * 1.3) * 0.22 + kick
        if t < lineJoyUntil { turn += sin(t * 13 + CGFloat(i) * 1.9) * 0.4 }
        let hipW = toWorld(hip)
        var want = toWorld(hip + (g * d + out * o) * reach)
        if abs(turn) > 0.0001 { want = hipW + (want - hipW).rotated(by: turn) }
        // (Drawn in: folded forward under the head, on the belly side,
        // wherever the ground is — ready to reach out that way.)
        if tuck > 0 {
            let ready = toWorld(hip + V2(k == 0 ? 0.3 : 0.18, -0.5) * reach)
            want = V2.lerp(want, ready, tuck)
        }
        // (Held toward its place by the leg, and slowed a little by the air
        // as the body carries it about.)
        var a = (want - freeFoot[i]) * 120 - (freeFootVel[i] - vel) * 9 - freeFootVel[i] * 1.5
        // The wind streams the legs hanging free out to one side.
        if weatherOnIt, !sheltered { a.x += windPush * 1.4 }
        freeFootVel[i] += a * dt
        freeFoot[i] += freeFootVel[i] * dt
        // Never further from the hip than the leg reaches, nor folded up
        // in under it: turned about quickly, a foot left behind goes round
        // the hip, not through it.
        let most = reach * 0.97 * sc, least = reach * 0.45 * sc
        let off = freeFoot[i] - hipW
        if off.length > most { freeFoot[i] = hipW + off.normalized * most }
        if off.length < least, off.length > 0.001 {
            let n = off.normalized
            freeFoot[i] = hipW + n * least
            let inward = (freeFootVel[i] - vel).dot(n)
            if inward < 0 { freeFootVel[i] -= n * inward }
        }
        return toLocal(freeFoot[i])
    }

    /// Part way from one place for a foot to another by an arc round the
    /// hip, at arm's length, rather than straight across — which could
    /// take it in through the hip and fold the leg up double. The way
    /// round (`turn`, kept from one frame to the next) goes on as it began:
    /// an end moving on round past the far side of the hip takes the arc
    /// on round with it, rather than flipping it over to the other side.
    /// (`fold`: a leg brought a long way round draws its foot in part way,
    /// bending at the knee as it goes, rather than sweeping round held out
    /// straight.)
    private static func roundHip(_ a: V2, _ b: V2, hip: V2, _ u: CGFloat, turn: inout CGFloat?, fold: CGFloat = 0) -> V2 {
        let ra = a - hip, rb = b - hip
        guard ra.length > 1, rb.length > 1 else { turn = nil; return V2.lerp(a, b, u) }
        var d = angleDelta(ra.angle, rb.angle)
        if let was = turn {
            while d - was > .pi { d -= 2 * .pi }
            while d - was < -.pi { d += 2 * .pi }
        }
        turn = d
        let drawnIn = 1 - fold * sin(u * .pi) * min(abs(d) / 1.5, 1)
        return hip + V2.angle(ra.angle + d * u) * (lerp(ra.length, rb.length, u) * drawnIn)
    }

    // MARK: - Debug

    /// Tools only: no decisions of its own while on the line, so a film can
    /// hold it there.
    var debugCalm = false

    /// Tools only: hangs it from `anchor` on a line `length` long, swinging
    /// if `swing`, with a starting angular velocity.
    func debugHang(at anchorPoint: V2, length: CGFloat, swing: Bool, kick: CGFloat = 0) {
        pos = anchorPoint + V2(0, -length)
        vel = .zero
        attachWeb(at: anchorPoint)
        webLen = length
        webLenTarget = length
        webAngle = 0
        webAngleVel = kick
        webStyle = swing ? .swing : .hang
        swingPumping = false
        swingHalfSwings = 0
        swingReleaseAfter = 99      // stays on the line for the tools to watch
        decisionIn = 99
        debugCalm = true
    }

    /// Tools only: shows an emote by name.
    func debugEmote(_ name: String) {
        switch name {
        case "exclaim": setEmote(.exclaim, 0.7)
        case "charge": setEmote(.charge, 1.6)
        case "hearts": setEmote(.hearts, 1.2)
        case "zzz": setEmote(.zzz, 3)
        default: break
        }
    }

    /// Tools only: the pendulum's state.
    var debugSwing: (angle: CGFloat, angVel: CGFloat) { (webAngle, webAngleVel) }

    /// Tools only: pays out or hauls in the line to `length` (as it would
    /// read hanging from the spinnerets; short enough to reach the top, all
    /// the way up).
    func debugLineTo(_ length: CGFloat) {
        guard mode == .dangling else { return }
        webLenTarget = length + (length < lineTop + 8 * config.scale ? 0 : lineRef)
        if webStyle == .hang { decisionIn = max(decisionIn, 3.5) }
    }

    /// Tools only: turning end for end on a line — how far the line is
    /// drawn in to its middle, how far round it is, and into its climbing
    /// stance.
    var debugTurn: (grip: CGFloat, upness: CGFloat, climb: CGFloat, ref: CGFloat) {
        (lineGrip, upness, climbLayout, lineRef)
    }

    /// Tools only: on a line, each foot in the world, whether it has hold
    /// of the silk (and is not reaching on), and how far round it is to
    /// face up the line.
    var debugLineFeet: (feet: [(world: V2, holding: Bool)], upness: CGFloat) {
        guard mode == .dangling else { return ([], 0) }
        let feet = legs.indices.map { i -> (world: V2, holding: Bool) in
            let holds = Spider.lineHang[i] != nil || frontHoldsWas >= 1
            return (toWorld(legs[i].foot), holds && !legs[i].swinging && legs[i].lift < 0.05)
        }
        return (feet, upness)
    }

    /// Tools only: the held stretch of line as drawn, in the world — and,
    /// rolling over, where the silk comes in along the belly to it.
    var debugThread: (a: V2, b: V2)? {
        guard let th = pose().thread else { return nil }
        let (sx, sy) = bodySquash()
        let g = SpiderRenderer.ground
        func drawn(_ v: V2) -> V2 { toWorld(V2(v.x * sx, g + (v.y - g) * sy)) }
        return (drawn(th.a), drawn(th.b))
    }
    var debugThreadVia: V2? {
        guard let via = pose().threadVia else { return nil }
        let (sx, sy) = bodySquash()
        let g = SpiderRenderer.ground
        return toWorld(V2(via.x * sx, g + (via.y - g) * sy))
    }

    /// Tools only: the line's length and where it is heading.
    var debugLine: (len: CGFloat, target: CGFloat, style: String, pumping: Bool) {
        (webLen, webLenTarget, webStyle == .swing ? "swing" : "hang", swingPumping)
    }

    /// Tools only: going over the top of what its line hangs from (or down
    /// off its line onto something), and how far through that it is (0…1),
    /// if it is.
    var debugMantle: CGFloat? { mantle.map { clamp($0.t / $0.dur, 0, 1) } }

    /// Tools only: what it has been told to do on its line, if anything,
    /// and the plan it is working through.
    var debugOrder: String {
        let order = lineOrder.map { "\($0)" } ?? "-"
        return order + " " + webPlan.map { "\($0)" }.joined(separator: ",")
    }

    /// Tools only: is the pointer where a hanging spider would go to look at it?
    var debugCursorNear: Bool {
        config.approachCursor && cursor.y < webAnchor.y - 60 && abs(cursor.x - webAnchor.x) < 120 * config.scale && t - lastUserActivity < 6
    }

    /// Tools only: per leg, why it is not down (settling, lifted, off the edge).
    var debugFeetWhy: String {
        legs.enumerated().map { i, leg in
            let off = leg.foot.distance(to: groundFoot(leg.foot))
            return String(format: "%d:%@%@%@", i, leg.settle >= 0 ? String(format: "s%.2f", leg.settle) : "", leg.lift >= 0.05 ? String(format: "L%.2f", leg.lift) : "",
                          off >= 1.5 ? String(format: "o%.0f", off) : "")
        }.joined(separator: " ") + " " + debugActivity
    }

    /// Tools only: each foot — where it is, where it rests, and where the
    /// edge-finder puts each, in world points.
    var debugFeet: [(foot: V2, placed: V2, rest: V2, restPlaced: V2)] {
        let profile = SpiderRenderer.profileAmount(yaw: yaw)
        return legs.indices.map { i in
            let r = SpiderRenderer.rig(i, profile: profile, look: look).foot
            return (toWorld(legs[i].foot), toWorld(groundFoot(legs[i].foot)), toWorld(r), toWorld(groundFoot(r)))
        }
    }

    /// Tools only: each foot in the world, and whether it is meant to be
    /// down (standing, not stepping or lifted) — to check it really is.
    var debugPlanted: [(world: V2, planted: Bool)] {
        legs.map { (toWorld($0.foot), mode == .attached && !$0.swinging && $0.settle < 0 && $0.lift < 0.05) }
    }

    /// Tools only: every foot is down on the surface it is standing on —
    /// planted, not mid-step, and on the edge itself.
    var debugFeetDown: Bool {
        guard mode == .attached else { return false }
        return legs.allSatisfy { leg in
            leg.settle < 0 && leg.lift < 0.05 && !leg.swinging && leg.foot.distance(to: groundFoot(leg.foot)) < 1.5
        }
    }

    /// Tools only: how taken it is with the pointer right now.
    var debugInterest: CGFloat { interest }
    /// Tools only: how it is following the pointer — interest, the
    /// smoothed bearing and side, where the legs and the head are aiming.
    var debugTrack: String {
        String(format: "int %.2f bear %+.2f side %+.0f legsT %+.2f headT %+.2f busy %d near %.1f/%.1f wig %.1f d %.0f", interest, interestBearing, interestSide,
               interestYawTarget, headYawTarget, preoccupied ? 1 : 0, cursorNearFor, boredAfter, cursorWiggle, cursor.distance(to: pos))
    }

    /// Tools only: each leg's place in the gait and its step, one line.
    var debugLegTiming: String {
        legs.enumerated().map { i, l in
            let ph = (gaitPhase + l.phase).truncatingRemainder(dividingBy: 1)
            return String(format: "%d:%@ph%.3f p0%.3f sh%.3f L%.2f f%.1f,%.1f st%.2f", i, l.swinging ? "S" : (l.skipSwing ? "k" : "-"), ph, l.swingPh0, l.swingShift, l.lift, l.foot.x, l.foot.y, l.settle)
        }.joined(separator: " ") + String(format: " G%.3f", gaitPhase)
    }

    /// Tools only: which controller has the legs, and the body's walking speed.
    var debugGait: (controller: String, speed: CGFloat) { ("\(legController)", speed) }

    /// Tools only: which way along its edge it is going and which way it
    /// faces (±1 each), and the sprite's yaw.
    var debugDirs: (walk: CGFloat, facing: CGFloat, yaw: CGFloat) { (walkDir, facing, yaw) }

    /// Tools only: the mood it is in and for how much longer, whether it
    /// may turn back yet, and the decision clock.
    var debugWhim: String {
        String(format: "%@ %.1fs%@ next %.2f%@", "\(mood)", Double(moodUntil - t), mayTurnBack ? "" : " keeping-way",
               Double(decisionIn), atLeisure ? "" : " busy")
    }

    /// Tools only: the carriage it walks with, as it has it on right now —
    /// and its yaw, head turn and head cock.
    var debugCarriage: String {
        String(format: "%@ turn %.2f look %.2f pitch %.2f nod %.2f tail %.2f lift %.1f cock %.2f | yaw %.2f head %.2f cocked %.2f%@%@",
               worn.kind.rawValue, Double(worn.turn), Double(worn.look), Double(worn.pitch), Double(worn.nod), Double(worn.tail),
               Double(worn.lift), Double(worn.cock), Double(yaw), Double(headTurn), Double(cock.value),
               checkIn != nil ? " [checking in]" : "", eyesOnYou ? " [eyes on you]" : "")
            + String(format: " beat turn %.2f look %.2f nod %.2f%@ eyes %.2f,%.2f", Double(beatTurn), Double(beatLook), Double(beatNod),
                     idleEyes ? " idle-eyes" : "", Double(lookSpring.value.x), Double(lookSpring.value.y))
    }
    /// Tools only: how far round toward you it is walking (0 side on), and
    /// whether it is on its feet going somewhere.
    var debugTurnedNow: (turn: CGFloat, onFoot: Bool) {
        (1 - abs(yaw), mode == .attached && Spider.onFoot.contains(activity) && speed > 1)
    }

    /// Tools only: walk on for `seconds` carrying itself this way (`turn`
    /// overriding how far round, for the turned ones).
    func debugCarry(_ kind: String, turn: CGFloat? = nil, for seconds: CGFloat) {
        guard let k = CarriageKind(rawValue: kind) else { return }
        debugWalk(for: seconds)
        var c: Carriage
        switch k {
        case .turned, .lookingOn, .sassy, .shifty:
            c = turnedCarriage(sneaking: k == .shifty, hurrying: false)
            var tries = 0
            while c.kind != k, tries < 200 { c = turnedCarriage(sneaking: k == .shifty, hurrying: false); tries += 1 }
        default:
            c = sideOnCarriage(k)
        }
        if let turn { c.turn = turn }
        carriage = c
        carriageFor = .walk
        carriageUntil = t + seconds + 1
    }

    /// Tools only: one of its little moments, now.
    func debugBeat(_ name: String) {
        switch name {
        case "doubleTake": beginActivity(.doubleTake, dur: 2.3); decisionIn = 4
        case "doubleTakeWalk": startDoubleTake(); decisionIn = 6
        case "sigh": beginActivity(.sigh, dur: 2.1); decisionIn = 3.5
        case "nod": nod(times: 2)
        case "shake": shakeHead()
        case "wink": wink()
        case "slowBlink": slowBlink()
        case "palps": palpFrom = [t + 0.1, t + 0.5]; palpNext = 5
        case "cock": standCock = 0.25; beginActivity(.stare, dur: 3); cockFor = activityStarted; cockIn = 9; decisionIn = 4
        default: break
        }
    }

    /// Tools only: the clock and the aim of whatever it is doing.
    var debugActivity: String {
        String(format: "%@ %.2f/%.2f jump=%@ poised=%d stalls=%d", "\(activity)", Double(activityTime), Double(activityDur),
               pendingJump.map { "\(Int($0.x)),\(Int($0.y))" } ?? "-", cursorPoised ? 1 : 0, cursorStalls)
    }

    var debugState: String {
        let m: String
        switch mode {
        case .attached: m = "attached"
        case .airborne: m = air == .jump ? "jump" : (air == .thrown ? "thrown" : "fall")
        case .dangling: m = webStyle == .swing ? "swinging" : "dangling"
        case .held:     m = "held"
        case .nesting:  m = nestPhase == .building ? "building" : "nesting"
        case .clinging: m = "clinging"
        }
        let hunt: String
        switch cursorHunt {
        case .none: hunt = ""
        case .stalking: hunt = " [stalking]"
        case .pouncing: hunt = " [pouncing]"
        case .clinging: hunt = ""
        }
        return (mode == .attached ? "\(m):\(activity) on \(anchor.loopID)" + (build != nil ? " [spinning]" : "") : m) + hunt
    }

    /// Tools only: which way the edge it is standing on faces — its
    /// normal's y: 1 on top of something, 0 up a side, -1 underneath.
    var debugFooting: CGFloat {
        guard mode == .attached, let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return 0 }
        return loop.segs[anchor.segIdx].normal.y
    }

    /// Tools only: its footing goes from under it, as if the surface had
    /// slid away — a fall, with whatever line it means to take.
    func debugFall() {
        guard mode == .attached else { return }
        detachAndFall()
    }

    func debugAttach(loopID: String, segIdx: Int, t: CGFloat, dir: CGFloat) {
        guard let loop = map.loop(loopID), segIdx < loop.segs.count else { return }
        let seg = loop.segs[segIdx]
        mode = .attached
        anchor = Anchor(loopID: loopID, segIdx: segIdx, t: t)
        walkDir = dir
        pos = seg.point(at: t)
        anchorPos = pos
        anchorValid = true
        legFramePos = pos
        heading = seg.angle
        headingTarget = heading
        headingVel = 0
        facing = dir
        yaw = dir
        grounded.reset(1)
        legFrameHeading = heading
        travelLocal = V2(1, 0)
        vel = .zero
        legMode = .planted
        for i in legs.indices {
            legs[i].foot = legs[i].rest
            legs[i].footVel = .zero
            legs[i].swinging = false
            legs[i].lift = 0
        }
        detachWeb(fade: false)
        webAlpha.reset(0)
        kneeShape = []
        footWorld = []
    }

    func debugJump(to point: V2) {
        startJump(to: point)
    }

    func debugWalk(for seconds: CGFloat) {
        beginActivity(.walk, dur: seconds)
        bout = 1
        boutBob = 1
        decisionIn = seconds
    }

    /// Tools only: walks on without stopping to look about on the way.
    func debugNoPauses() { walkPauseAt = 99 }

    /// Tools only: carries itself this way on its walk (normal, bouncy,
    /// tiptoe, lumber).
    func debugGaitStyle(_ name: String) {
        switch name {
        case "bouncy": gaitStyle = .bouncy
        case "tiptoe": gaitStyle = .tiptoe
        case "lumber": gaitStyle = .lumber
        default: gaitStyle = .normal
        }
    }

    func debugActivity(_ name: String, for seconds: CGFloat) {
        let table: [String: Activity] = [
            "walk": .walk, "sneak": .sneak, "scurry": .scurry, "look": .look, "rest": .rest,
            "groom": .groom, "sleep": .sleep, "wave": .wave, "startle": .startle,
            "peek": .peek, "stretch": .stretch, "shake": .shake, "wiggle": .wiggle,
            "bounce": .bounce, "curious": .curious, "fidget": .fidget, "scratch": .scratch,
            "armsUp": .armsUp, "roll": .roll, "dance": .dance, "glance": .glance, "peer": .peer,
            "pushup": .pushup, "legStretch": .legStretch, "spin": .spin, "eat": .eat, "watch": .watch,
            "peekaboo": .peekaboo, "greet": .greet, "drum": .drum, "stare": .stare, "hop": .hop,
            "fasten": .fasten, "groove": .groove, "brace": .brace, "bask": .bask,
            "doubleTake": .doubleTake, "sigh": .sigh,
        ]
        if name == "turn" {
            turnTo(-walkDir, then: .look, for: 1)
            return
        }
        if name == "swing" {
            if mode == .dangling { workUpSwing() } else { _ = startSwing() }
            return
        }
        if name == "peekaboo" { playPeekaboo(); return }
        if name == "bed" { bedBoundUntil = t + 60; goToBed(); return }
        if name == "build" { buildHammock(); return }
        if name == "groove" { startGroove(); return }
        if name == "nap" { napInHammock(); return }
        guard let a = table[name] else { return }
        beginActivity(a, dur: seconds)
        decisionIn = seconds + 5
    }

    // MARK: - Pose out

    /// How the sprite is scaled about its ground line right now: crouching
    /// squashes the whole thing down onto its feet, a landing splats it
    /// wide.
    /// How far a full crouch lets the body down, in sprite units.
    private static let crouchDrop: CGFloat = 7.5

    /// A hop on the spot: long enough for all of it — the gather, the push,
    /// the flight and the landing — with a beat left to stand after.
    static let hopDur: CGFloat = 0.62
    /// Up on its toes at the moment the feet leave, and how much higher the
    /// top of the hop is, in sprite units.
    private static let hopTakeoff: CGFloat = 2
    private static let hopHeight: CGFloat = 7
    /// How high the feet come up off the ledge at the top of it.
    private static let hopFeet: CGFloat = 6

    /// Where a hop is: gathering itself (0), pushing off (1), in the air
    /// (2), coming down onto its legs (3), standing after (4) — and how far
    /// through that stage. The push ends at the pace the flight begins at,
    /// and the landing takes it on at the pace the flight ends at, so the
    /// body carries its speed through each hand-off.
    private func hopPhase() -> (stage: Int, v: CGFloat) {
        let push: CGFloat = 0.08, flight: CGFloat = 0.22, land: CGFloat = 0.16
        let gather = clamp(activityDur - push - flight - land, 0.1, 0.22)
        var s = activityTime
        for (i, d) in [gather, push, flight, land].enumerated() {
            if s < d { return (i, s / d) }
            s -= d
        }
        return (4, 1)
    }

    private func bodySquash() -> (stretch: CGFloat, fatten: CGFloat) {
        // Only a touch of squash for a crouch — the lowering is the body
        // coming down on its legs (see `crouchDrop`).
        // (And coming down on the beat, dancing.)
        let squash = (1 - clamp(crouch.value, 0, 1) * 0.07) * (1 - gf.squash)
        return (clamp(stretch.value * (1 + (1 - squash) * 0.5), 0.74, 1.22),
                clamp(fatten.value * squash, 0.66, 1.26))
    }

    private var bodyPitchNow: CGFloat { clamp(pitch.value + runNose + gf.pitch, -0.6, 0.6) }

    /// Leg `i` as drawn: hip and foot where the pose puts them, and the
    /// knee the leg models ask for. The lean turns the hips (and a foot in
    /// the air) about the pivot; the squash and stretch scales the whole
    /// sprite about its ground line, and the feet are taken out of it, so a
    /// splat or a crouch does not shove a planted foot along the ledge (or,
    /// tilted, into it) — nor, on a line, a foot off the silk it holds, or a
    /// hanging one out of where it hangs, as it bounces on the end of it.
    /// `trueLength`: the knee where the leg's own thigh and shin put it,
    /// bent the way it bends standing (the natural walk's legs).
    private func modelLeg(_ i: Int, profile: CGFloat, trueLength: Bool = false) -> (hip: V2, foot: V2, knee: V2) {
        let bp = bodyPitchNow
        let shift = V2(-bp * 8, bp * 2)
        let pivot = SpiderRenderer.leanPivot
        func leaned(_ v: V2) -> V2 { pivot + (v - pivot).rotated(by: bp) + shift }
        let feetPlaced = mode == .attached || mode == .nesting || onLine
        let g = SpiderRenderer.ground
        let leg = legs[i]
        var hip = SpiderRenderer.rig(i, profile: profile, look: look).hip
        var foot = leg.foot
        if abs(bp) > 0.0005 {
            hip = leaned(hip)
            let inAir = clamp((foot.y - (g + 3)) / 10, 0, 1)
            if inAir > 0 { foot = V2.lerp(foot, leaned(foot), inAir) }
        }
        // The knee is worked out where the leg is drawn — hip squashed with
        // the body, foot where it really is — so the leg keeps its true
        // lengths and a lowered body folds it, rather than the squash
        // flattening it; then it is put back into the squashed frame the
        // renderer draws the legs in, like the foot.
        let sq = bodySquash()
        let drawnHip = V2(hip.x * sq.stretch, g + (hip.y - g) * sq.fatten)
        let drawnFoot = feetPlaced ? foot : V2(foot.x * sq.stretch, g + (foot.y - g) * sq.fatten)
        let drawnKnee: V2
        if trueLength {
            let r = SpiderRenderer.rig(i, profile: profile, look: look)
            let side: CGFloat = (r.foot - r.hip).cross(r.knee - r.hip) >= 0 ? 1 : -1
            var thigh = (r.knee - r.hip).length, shin = (r.foot - r.knee).length
            // (Walking the refined way, a leg reaching well out gives a
            // little: see `refGive`.)
            if refinedWalk, refGiveNow.count == legs.count {
                thigh *= refGiveNow[i]
                shin *= refGiveNow[i]
            }
            drawnKnee = Spider.twoBoneKnee(hip: drawnHip, foot: drawnFoot, thigh: thigh, shin: shin, side: side)
        } else if let bend = legBend[i] {
            let own = SpiderRenderer.kneeIK(leg: i, hip: drawnHip, foot: drawnFoot, away: bend, profile: profile, look: look)
            if let other = legBones[i] {
                // Borrowed proportions come in as the foot rises off the
                // ledge, not all at once at the start of the gesture. (On
                // a line they are the leg's own; see `lineBones`.)
                let w = onLine ? 1 : smoothstep(clamp((leg.foot.y - leg.rest.y) / 22, 0, 1))
                let borrowed = SpiderRenderer.kneeIK(leg: other, hip: drawnHip, foot: drawnFoot, away: bend, profile: profile, look: look)
                drawnKnee = V2.lerp(own, borrowed, w)
            } else {
                drawnKnee = own
            }
        } else {
            drawnKnee = SpiderRenderer.knee(leg: i, hip: drawnHip, foot: drawnFoot, lift: leg.lift, profile: profile, look: look)
        }
        if feetPlaced { foot = V2(foot.x / sq.stretch, g + (foot.y - g) / sq.fatten) }
        let knee = V2(drawnKnee.x / sq.stretch, g + (drawnKnee.y - g) / sq.fatten)
        return (hip, foot, knee)
    }

    /// The knee of a leg with a thigh and shin of these lengths, its foot at
    /// `foot`, bent to `side` (+1 to the left of the hip-to-foot line).
    private static func twoBoneKnee(hip: V2, foot: V2, thigh a: CGFloat, shin b: CGFloat, side: CGFloat) -> V2 {
        var d = foot - hip
        var dist = d.length
        if dist < 0.01 { d = V2(1, 0); dist = 1 }
        let dir = d / dist
        let reach = clamp(dist, abs(a - b) + 0.01, a + b)
        let x = (a * a - b * b + reach * reach) / (2 * reach)
        let h = max(a * a - x * x, 0).squareRoot()
        return hip + dir * x + dir.perp * (h * side)
    }

    /// A knee as a shape: how far along the hip-to-foot line it sits and
    /// how far out to the side, both as fractions of that line's length.
    private static func kneeShape(hip: V2, foot: V2, knee: V2) -> V2 {
        let d = foot - hip
        let len = max(d.length, 1)
        let u = d / len
        let k = knee - hip
        return V2(k.dot(u) / len, u.cross(k) / len)
    }

    private static func knee(from shape: V2, hip: V2, foot: V2) -> V2 {
        let d = foot - hip
        let len = max(d.length, 1)
        let u = d.length > 0.001 ? d / d.length : V2(1, 0)
        // (x, y) -> along u, and out along u's left normal: the inverse of
        // the cross product above.
        return hip + u * (shape.x * len) + V2(-u.y, u.x) * (shape.y * len)
    }

    /// The knees ease between shapes. Two different leg models answer for
    /// the knee (a bend held for a pose, the rest shape swung about the hip
    /// otherwise) and either can flip the bend from one side to the other
    /// from one frame to the next — the pops that make a leg look broken.
    /// A foot moving carries its knee with it rigidly, so nothing lags; only
    /// a change of shape is eased, and a bend going over to the other side
    /// passes through a straightened leg, as a real one does.
    private func updateKnees(dt: CGFloat) {
        let profile = SpiderRenderer.profileAmount(yaw: yaw)
        let fresh = kneeShape.count != legs.count
        if fresh { kneeShape = Array(repeating: .zero, count: legs.count) }
        if kneeShapeVel.count != legs.count { kneeShapeVel = Array(repeating: .zero, count: legs.count) }
        let k = 1 - exp(-dt * 24)
        let line = onLine
        // On a surface the knees come under the same limit as the feet: a
        // knee riding a hip-to-foot line that swings round fast (a foot
        // passing close under the hip) is held to a movement too.
        let limit = (mode == .attached || mode == .nesting) && activity != .roll && !fresh && !Spider.debugRawLegs
            && kneeWorld.count == legs.count && kneeWorldVel.count == legs.count && dt > 0
            && pos.distance(to: kneeLimitPos) < 30 * config.scale
        kneeLimitPos = pos
        if kneeWorld.count != legs.count { kneeWorld = Array(repeating: .zero, count: legs.count) }
        if kneeWorldVel.count != legs.count { kneeWorldVel = Array(repeating: .zero, count: legs.count) }
        if lineSide.count != legs.count {
            lineSide = Array(repeating: 1, count: legs.count)
            lineSideAim = Array(repeating: 1, count: legs.count)
            lineSideVel = Array(repeating: 0, count: legs.count)
            lineBoneLen = Array(repeating: V2(20, 25), count: legs.count)
        }
        // Just up off a line onto a ledge, the knees come over to standing
        // as they go over on a line, not all at once: the feet are still
        // stepping up off the silk.
        let offLine = climbedOnto && mode == .attached && t - landedAt < 0.45 && lineKneesLive
        defer { lineKneesLive = (line || offLine) && !fresh }
        // The natural walk's legs keep their true lengths: its knees come in
        // over a moment as it takes the legs, and go as it hands them on.
        let natural = (naturalWalk || refinedWalk) && legController == .gait && !line
        for i in natKnee.indices {
            natKnee[i] = natural ? min(natKnee[i] + dt / Spider.natKneeTime, 1) : max(natKnee[i] - dt / Spider.natKneeTime, 0)
            if fresh { natKnee[i] = natural ? 1 : 0 }
        }
        let classicLegs = mode == .attached && !line && legController == .gait && activity != .roll && !Spider.debugRawLegs
        kneeLocal = legs.indices.map { i in
            let j = modelLeg(i, profile: profile)
            // On a surface a knee never folds down through what it stands
            // on. The leg model swings the standing shape round the hip with
            // the foot, which for a foot left behind its hip coming round a
            // corner (a front foot still on the floor as it comes down off a
            // block, say) puts the knee under the ground; the leg bends the
            // other way instead, same bones, knee up — going over as a
            // movement, through the leg held straight, and only once the
            // knee is plainly under, so one right at the ground does not
            // flick from side to side. (Under is under the ground line it
            // stands on, or — rounding an inside corner, where that line is
            // turned away from the floor — under the edge itself.)
            var model = natKnee[i] > 0 ? modelLeg(i, profile: profile, trueLength: true).knee : j.knee
            // (Over the outside of a corner the line the body stands on runs
            // off over the drop: there only the edge itself is the ground.)
            var overDrop = false
            if mode == .attached, !line, footCornered(i) >= 0.5, let loop = map.loop(anchor.loopID) {
                let s = max(config.scale, 0.05)
                overDrop = surfaceSide(toWorld(V2(model.x, SpiderRenderer.ground - refRide / s)), loop) > s
            }
            let under = mode == .attached && !line
                ? max(overDrop ? -.greatestFiniteMagnitude : SpiderRenderer.ground - model.y,
                      depthUnderEdge(kneeWorldPoint(model)) / max(config.scale, 0.05))
                : SpiderRenderer.ground - model.y
            // (Walking the refined way, a leg kept at its own length cannot
            // go over to its other bend without being drawn shorter or longer
            // on the way: its feet are put where its knees stay out of the
            // ground instead, and the knee is left as the bones put it.)
            let keepBend = refinedWalk && natKnee[i] >= 1
            let wantOver: CGFloat = mode == .attached && !line && !fresh && !keepBend
                ? (under > 2 ? 1 : (under < -1 ? 0 : kneeOverAim[i])) : 0
            kneeOverAim[i] = wantOver
            kneeOver[i] = wantOver > kneeOver[i] ? min(kneeOver[i] + dt / Spider.kneeOverTime, 1)
                                                 : max(kneeOver[i] - dt / Spider.kneeOverTime, 0)
            if kneeOver[i] > 0 {
                // The thigh swings over about the hip, keeping its length,
                // by way of pointing straight at the foot: never in through
                // the hip, where the leg would look snapped off.
                let k = model - j.hip
                let toFoot = (j.foot - j.hip).angle
                let side = 1 - 2 * smoothstep(kneeOver[i])
                model = j.hip + V2.angle(toFoot + angleDelta(toFoot, k.angle) * side) * k.length
            }
            let want = Spider.kneeShape(hip: j.hip, foot: j.foot, knee: model)
            var local: V2
            if fresh {
                kneeShape[i] = want
                local = Spider.knee(from: kneeShape[i], hip: j.hip, foot: j.foot)
            } else if line && legBend[i] != nil || offLine {
                local = lineKnee(i, hip: j.hip, foot: j.foot, bend: legBend[i] ?? .zero, model: line ? nil : j.knee,
                                 profile: profile, from: Spider.knee(from: kneeShape[i], hip: j.hip, foot: j.foot), dt: dt)
                // (Kept up, for whatever has the legs next.)
                kneeShape[i] = Spider.kneeShape(hip: j.hip, foot: j.foot, knee: local)
                kneeShapeVel[i] = .zero
            } else {
                kneeShape[i] = kneeShape[i] + (want - kneeShape[i]) * k
                kneeShapeVel[i] = .zero
                local = Spider.knee(from: kneeShape[i], hip: j.hip, foot: j.foot)
                // However the shape eases, neither bone is drawn much longer
                // than the leg's model has it. A shape taken with the foot
                // right by its hip (a landing, a foot swept round a corner)
                // is all out of proportion, and laid on the leg as it
                // stretches out again it throws the knee out to two or three
                // times the thigh's length. (A knee going over to the other
                // side passes between the two bends, inside both bones'
                // reach, and is left to.)
                let thigh = model.distance(to: j.hip) * Spider.boneGive + Spider.boneSlack
                let shin = j.foot.distance(to: model) * Spider.boneGive + Spider.boneSlack
                if local.distance(to: j.hip) > thigh || j.foot.distance(to: local) > shin {
                    // As little of the way back to the model's knee as puts
                    // both within that.
                    var lo: CGFloat = 0, hi: CGFloat = 1
                    for _ in 0..<10 {
                        let m = (lo + hi) / 2, k = V2.lerp(local, model, m)
                        if k.distance(to: j.hip) > thigh || j.foot.distance(to: k) > shin { lo = m } else { hi = m }
                    }
                    local = V2.lerp(local, model, hi)
                    kneeShape[i] = Spider.kneeShape(hip: j.hip, foot: j.foot, knee: local)
                }
                if natKnee[i] > 0 {
                    // (Taken all the way, exactly where the bones put it.)
                    local = V2.lerp(local, model, smoothstep(natKnee[i]))
                    kneeShape[i] = Spider.kneeShape(hip: j.hip, foot: j.foot, knee: local)
                } else if classicLegs {
                    local = cornerKnee(i, hip: j.hip, foot: j.foot, knee: local, profile: profile)
                }
            }
            var w = kneeWorldPoint(local)
            // (A knee on the leg's true bones is wherever hip and foot put
            // it: held back, it would draw them off their lengths. The feet
            // are limited already.)
            if limit, natKnee[i] < 1 {
                if Spider.limitJolt(&w, last: &kneeWorld[i], vel: &kneeWorldVel[i], cap: Spider.footJolt * config.scale * landingJolt, dt: dt) {
                    return kneeLocalPoint(w)
                }
            } else {
                kneeWorldVel[i] = dt > 0 ? (w - kneeWorld[i]) / dt : .zero
                kneeWorld[i] = w
            }
            return local
        }
    }
    private var kneeLimitPos: V2 = .zero

    /// The classic walk draws a leg's bones longer the further its foot is
    /// from its hip. Round a window's corner the feet end up further out
    /// than on any flat edge — a hind foot still back on the top as it goes
    /// over and down the side, front feet reaching down it — and the legs
    /// come out visibly longer there. There each bone is held to the most a
    /// flat walk draws it (`flatThigh`, `flatShin`), the knee opening out to
    /// make up the reach instead. Only round a corner — where the edge
    /// under the foot is turned from the body's own (`edgeTurn`), or off
    /// the line a flat edge would be on (out on a window's rounded corner,
    /// where it falls away), or the foot is down off that line — eased in
    /// over a little of each, so on a flat edge the legs are exactly as
    /// they were.
    private func cornerKnee(_ i: Int, hip: V2, foot: V2, knee: V2, profile: CGFloat) -> V2 {
        let w = footCornered(i)
        guard w > 0 else { return knee }
        let r = SpiderRenderer.rig(i, profile: profile, look: look)
        let most = (thigh: (r.knee - r.hip).length * Spider.flatThigh[i], shin: (r.foot - r.knee).length * Spider.flatShin[i])
        var a = knee.distance(to: hip), b = foot.distance(to: knee)
        guard a > most.thigh || b > most.shin else { return knee }
        a = min(a, most.thigh)
        b = min(b, most.shin)
        // (Never so short it cannot reach the foot.)
        let span = foot.distance(to: hip) + 0.5
        if a + b < span { a *= span / (a + b); b *= span / (a + b) }
        let bend = (foot - hip).cross(knee - hip)
        let side: CGFloat = abs(bend) > 0.5 ? (bend >= 0 ? 1 : -1) : ((r.foot - r.hip).cross(r.knee - r.hip) >= 0 ? 1 : -1)
        return V2.lerp(knee, Spider.twoBoneKnee(hip: hip, foot: foot, thigh: a, shin: b, side: side), w)
    }
    /// How much of a corner leg `i`'s foot is round, 0…1: none at all
    /// anywhere along a flat edge; all of it once the edge under the foot is
    /// turned well away from the line the body stands on (`edgeTurn`), or
    /// off that line — out on a window's rounded corner, where it falls
    /// away — or the foot is standing off it.
    private func footCornered(_ i: Int) -> CGFloat {
        let leg = legs[i]
        let flat = V2(leg.foot.x, SpiderRenderer.ground - refRide / max(config.scale, 0.05))
        var off = groundFoot(flat).distance(to: flat)
        if !leg.swinging, leg.settle < 0, leg.lift < 0.05 { off = max(off, abs(leg.foot.y - flat.y) - 0.5) }
        return max(smoothstep(clamp((edgeTurn(under: leg.foot) - 0.04) / 0.2, 0, 1)), smoothstep(clamp((off - 1) / 4, 0, 1)))
    }

    /// How far the edge nearest a foot (sprite-local) is turned from the
    /// line the body stands on, in radians: nothing all along a flat edge;
    /// the turn of the corner for a foot round one — a hind foot still on
    /// the floor as it goes up a wall, front feet down the side as it goes
    /// over the top.
    private func edgeTurn(under local: V2) -> CGFloat {
        guard let loop = map.loop(anchor.loopID), !loop.edge.isEmpty else { return 0 }
        let w = toWorld(local)
        var best = (d: CGFloat.greatestFiniteMagnitude, normal: V2(0, 1), point: V2.zero)
        for e in loop.edge where e.len > 0.5 {
            let (t, d) = projectOnSegment(w, e.a, e.b)
            if d < best.d { best = (d, e.normal, e.point(at: clamp(t, 0, e.len))) }
        }
        if let c = loop.onRoundedCorner(best.point) { best.normal = c.normal }
        let up = V2(0, 1).rotated(by: heading)
        return abs(angleDelta(up.angle, best.normal.angle))
    }

    /// The longest each leg's thigh and shin are drawn walking the classic
    /// way along a flat edge, as a share of the rig's (at the smallest
    /// size, whose strides are longest for it, in any manner of walk but a
    /// scurry), and a little over.
    private static let flatThigh: [CGFloat] = [1.53, 1.62, 1.40, 1.39, 1.53, 1.50, 1.41, 1.39]
    private static let flatShin: [CGFloat] = [1.66, 1.82, 1.46, 1.46, 1.63, 1.65, 1.46, 1.44]
    /// How far a point is behind the edge it stands on — inside the window,
    /// under the floor — in world points; negative in the open. Measured
    /// from the nearest stretch of edge that is square to it, so the far
    /// side of a corner does not count.
    private func depthUnderEdge(_ w: V2) -> CGFloat {
        guard let loop = map.loop(anchor.loopID) else { return -.greatestFiniteMagnitude }
        // (A window's corners are rounded: out in the corner of its square
        // outline there is no window, only air.)
        if loop.kind == .windowEdge, loop.cornerRadius > 0.5, loop.closed { return -surfaceSide(w, loop) }
        var best: (dist: CGFloat, depth: CGFloat)?
        for e in loop.edge where e.len > 0.5 {
            let t = (w - e.a).dot(e.dir)
            guard t > 0, t < e.len else { continue }
            let off = (w - e.point(at: t)).dot(e.normal)
            if best == nil || abs(off) < best!.dist { best = (abs(off), -off) }
        }
        return best?.depth ?? -.greatestFiniteMagnitude
    }

    /// How far each knee is through going over to its other bend, to keep
    /// it out of the ground it stands on (0 as the model has it, 1 over),
    /// the way it is going, and how long going over takes, in seconds.
    private var kneeOver: [CGFloat] = Array(repeating: 0, count: SpiderRenderer.legCount)
    private var kneeOverAim: [CGFloat] = Array(repeating: 0, count: SpiderRenderer.legCount)
    private static let kneeOverTime: CGFloat = 0.16
    /// How long the natural walk's knees take to come in, or go.
    private static let natKneeTime: CGFloat = 0.2
    /// How much longer than the leg model's an eased knee may draw either
    /// bone, as a share and then some, in sprite units (see `updateKnees`).
    /// Walking, small, with long strides for its size, the easing alone
    /// comes to within a few units of this; a knee thrown out by a shape
    /// taken right by the hip goes well past it.
    private static let boneGive: CGFloat = 1.8
    private static let boneSlack: CGFloat = 10
    /// How fast each knee's shape is changing (see `updateKnees`).
    private var kneeShapeVel: [V2] = []

    /// On a line, a knee is where the leg's own bones put it between hip
    /// and foot — so a leg is never drawn out longer than it is, or folded
    /// up shorter, however fast the foot goes — on the side of the leg it
    /// is bent to. That side goes round with the leg: a foot swinging
    /// round the hip carries its knee round with it, as a real one does,
    /// rather than flipping it over whenever the leg passes the way it
    /// means to bend (`legBend`). It goes over to the other side only once
    /// that is plainly the way to bend, and then on a spring, through the
    /// leg held straight out. Taking up a line, it starts from the knee as
    /// it was, and grows into the leg's proportions on a line
    /// (`lineBones`). (Stepping off it, it goes over to the side the
    /// standing leg's knee is on, `model`.)
    private func lineKnee(_ i: Int, hip: V2, foot: V2, bend: V2, model: V2? = nil, profile: CGFloat, from start: V2, dt: CGFloat) -> V2 {
        // Worked out where the leg is drawn, as `modelLeg` does.
        let sq = bodySquash()
        let g = SpiderRenderer.ground
        func drawn(_ v: V2) -> V2 { V2(v.x * sq.stretch, g + (v.y - g) * sq.fatten) }
        let dh = drawn(hip), df = drawn(foot)
        var d = df - dh
        var dist = d.length
        if dist < 0.01 { d = V2(1, 0); dist = 1 }
        let u = d / dist
        let across = u.perp
        if !lineKneesLive {
            let k = drawn(start) - dh
            lineBoneLen[i] = V2(max(k.length, 1), max(df.distance(to: drawn(start)), 1))
            lineSide[i] = k.dot(across) >= 0 ? 1 : -1
            lineSideAim[i] = lineSide[i]
            lineSideVel[i] = 0
        }
        let plain = bend.length > 0.01 ? across.dot(bend.normalized) : 0
        if abs(plain) >= 0.35 { lineSideAim[i] = plain > 0 ? 1 : -1 }
        if let m = model {
            let out = (drawn(m) - dh).dot(across)
            if abs(out) > 0.5 { lineSideAim[i] = out > 0 ? 1 : -1 }
        }
        // (Quicker stepping off, with every leg coming over at once.)
        let (k, c): (CGFloat, CGFloat) = model == nil ? (81, 18) : (256, 32)
        lineSideVel[i] += ((lineSideAim[i] - lineSide[i]) * k - lineSideVel[i] * c) * dt
        lineSide[i] = clamp(lineSide[i] + lineSideVel[i] * dt, -1, 1)
        let r = SpiderRenderer.rig(legBones[i] ?? i, profile: profile, look: look)
        let bones = V2(max((r.knee - r.hip).length, 1), max((r.foot - r.knee).length, 1))
        lineBoneLen[i] = lineBoneLen[i] + (bones - lineBoneLen[i]) * (1 - exp(-dt * 14))
        let a = lineBoneLen[i].x, b = lineBoneLen[i].y
        let reach = clamp(dist, abs(a - b) + 0.5, a + b - 0.5)
        let x = (a * a - b * b + reach * reach) / (2 * reach)
        let h = max(a * a - x * x, 0).squareRoot()
        let dk = dh + u * x + across * (h * lineSide[i])
        return V2(dk.x / sq.stretch, g + (dk.y - g) / sq.fatten)
    }
    /// Which side of its leg each knee is on, on a line (+1 or -1, and in
    /// between going over), the side it is going to, how fast it is going
    /// over; and the femur and tibia it is drawn with.
    private var lineSide: [CGFloat] = []
    private var lineSideAim: [CGFloat] = []
    private var lineSideVel: [CGFloat] = []
    private var lineBoneLen: [V2] = []
    private var lineKneesLive = false

    /// A drawn leg point (as `pose()` lays it out, with the squash and
    /// stretch) to the world, and back.
    private func kneeWorldPoint(_ l: V2) -> V2 {
        let sq = bodySquash()
        let g = SpiderRenderer.ground
        return toWorld(V2(l.x * sq.stretch, g + (l.y - g) * sq.fatten))
    }
    private func kneeLocalPoint(_ w: V2) -> V2 {
        let sq = bodySquash()
        let g = SpiderRenderer.ground
        let l = toLocal(w)
        return V2(l.x / max(sq.stretch, 0.01), g + (l.y - g) / max(sq.fatten, 0.01))
    }

    func pose() -> SpiderPose {
        var p = SpiderPose()
        p.pos = pos
        p.heading = heading
        p.spin = rollSpin
        p.ball = ball
        p.facing = clamp(yaw, -1, 1)
        p.grounded = clamp(grounded.value, 0, 1)
        p.scale = config.scale
        (p.stretch, p.fatten) = bodySquash()
        let mirror: CGFloat = yaw >= 0 ? 1 : -1
        var attach = silkAttachLocal()
        attach.x *= mirror
        p.silkAttach = pos + attach.rotated(by: heading) * config.scale
        p.time = t
        p.look = lookSpring.value
        p.blink = clamp(max(blinkValue, sleepiness.value, lid.value, slowBlinkNow), 0, 1)
        p.wink = winkNow
        p.headCock = cock.value
        p.palpNear = palpNow(0)
        p.palpFar = palpNow(1)
        p.happy = clamp(happy.value + pettingScore * 0.5 + fed * 0.3, 0, 1)
        if activity == .eat, mode == .attached { p.chew = 0.5 + 0.5 * sin(t * 11) }
        if activity == .drink, mode == .attached { p.chew = 0.25 + 0.25 * max(0, sin(t * 8)) }
        // A nibble at the pointer it has caught, now and then.
        if mode == .clinging { p.chew = max(0, sin(t * 7)) * (0.5 + 0.5 * sin(t * 0.9)) }
        p.headTilt = headTilt.value + gf.nod
        p.headTurn = headTurn
        p.abdomenTilt = abdomenTilt.value + gf.tail
        // It is drawn in front of everything, and it stays there: it never
        // slips behind a window. The one exception is peek-a-boo, where
        // hiding behind the edge of a window in front of the one it stands
        // on is the whole game — then the parts of it inside that window
        // are behind it.
        if mode == .attached, activity == .peekaboo, let loop = map.loop(anchor.loopID), loop.kind.onWindow {
            let r = 62 * config.scale
            let sprite = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            p.hiddenBy = map.occluders.filter { $0.depth < loop.depth && $0.rect.intersects(sprite) }.map { $0.rect }
            // Hiding: its two front feet stay out, gripping the edge — the
            // rest of it is behind the window and is not drawn.
            if let pk = peek, pk.stage == 1 || pk.stage == 2, anchor.segIdx < loop.segs.count {
                let seg = loop.segs[anchor.segIdx]
                let toEdge = seg.dir * (pk.edgeT - anchor.t)
                let along = seg.dir * (10 * config.scale)
                let across = surfaceNormal * (6 * config.scale)
                p.peekGrip = [toEdge - along + across, toEdge + along + across]
            }
        }
        p.startled = clamp(startled.value, 0, 1)
        p.sleep = clamp(sleepiness.value, 0, 1)
        p.abdomenSway = swayWobble.value(t * 1.4) * 0.14
            + sin(gaitPhase * .pi * 2) * (0.09 + worn.sway) * min(speed / 60, 1)
            + sin(wagPhase) * wag.value * 0.55
            + gf.sway
        p.emote = emote
        p.emoteT = emoteDur > 0 ? clamp(emoteTime / emoteDur, 0, 1) : 0
        p.emoteClock = emoteClock
        p.thought = thought
        p.grabbed = grabbed.value
        p.outfit = look
        p.surroundings = shownSurroundings
        p.name = name
        p.nameTag = clamp(nameTag.value, 0, 1)
        p.odometer = odometer
        let profile = SpiderRenderer.profileAmount(yaw: yaw)
        // The lean: body and hips turn about a point between the hips and
        // shift a little with it; a foot on the ground stays put, a foot in
        // the air goes with the body.
        let bp = bodyPitchNow
        p.bodyPitch = bp
        p.bodyShift = V2(-bp * 8, bp * 2)
        p.legs = legs.indices.map { i in
            let j = modelLeg(i, profile: profile)
            // The knee keeps the shape it has been easing toward, laid on
            // this frame's hip and foot.
            let knee = kneeLocal.count == legs.count ? kneeLocal[i] : j.knee
            return LegPose(hip: j.hip, knee: knee, foot: j.foot, lift: legs[i].lift)
        }
        if weatherOnIt || wet > 0 || snowOn > 0 || dust > 0 || !drops.isEmpty { weatherPose(&p) }
        if let from = buildThreadFrom, !webActive {
            p.web = (from, clamp(webAlpha.value, 0, 1), 0.15)
        } else if let shot = airShot, shot.progress > 0 {
            // The line on its way up to the mark.
            let tip = V2.lerp(p.silkAttach, shot.target, easeOutCubic(shot.progress))
            p.web = (tip, 0.9, 0)
        } else if webAlpha.value > 0.01 {
            let d = pos.distance(to: webAnchor)
            let slack = webActive ? clamp(1 - d / max(webLen + bungee.value, 1), 0, 1) : 0.3
            p.web = (webAnchor, clamp(webAlpha.value, 0, 1), webStyle == .swing ? 0 : slack)
        } else if mode == .attached, activity == .shoot {
            // The line on its way out.
            let tip = V2.lerp(p.silkAttach, shotTarget, easeOutCubic(shotProgress))
            p.web = (tip, 0.9, 0)
        }
        if p.web != nil, rope.live { p.webPoints = rope.points }
        // Making its entrance, nothing of it shows above the bottom of the
        // menu bar: see-through as the bar is, it is coming out from
        // behind it — and so is its line.
        if let e = entrance {
            let r = SpiderRenderer.drawRadius * config.scale + 40
            p.hiddenBy.append(CGRect(x: pos.x - r, y: e.barY, width: r * 2, height: r * 2 + 400))
            if let web = p.web, web.anchor.y > e.barY {
                let pts = p.webPoints.count >= 2 ? p.webPoints : [web.anchor, p.silkAttach]
                if let i = pts.firstIndex(where: { $0.y <= e.barY }) {
                    let a = pts[i - 1], b = pts[i]
                    let cut = V2.lerp(a, b, (a.y - e.barY) / max(a.y - b.y, 0.001))
                    p.webPoints = [cut] + pts[i...]
                    p.web = (cut, web.alpha, web.slack)
                } else {
                    p.web = (web.anchor, 0, web.slack)
                }
            }
        }
        if onLine, webActive, let web = p.web {
            // The held stretch of line, in sprite units — along the silk as
            // it lies there, out past the highest foot on it — plus, climbing,
            // the silk it has hauled in, gathered below the spinnerets.
            // (Taken out of the body's squash and stretch, which the sprite
            // is drawn with, so it lies on the line itself as the body
            // bounces on the end of it — as the feet holding it do.)
            let (sx, sy) = bodySquash()
            let g = SpiderRenderer.ground
            func unsquashed(_ v: V2) -> V2 { V2(v.x / sx, g + (v.y - g) / sy) }
            let a = silkAttachLocal()
            var len = min(heldStretch, (toLocal(webAnchor) - a).length)
            // (Never out past what the sprite can draw — turning round, the
            // line runs off to the side — the world's line has it beyond.)
            let most = SpiderRenderer.drawRadius - 8
            let ad = a.dot(lineDirLocal)
            let room = ad * ad - (a.lengthSquared - most * most)
            len = min(len, room > 0 ? max(-ad + room.squareRoot(), 0) : 0)
            p.thread = (unsquashed(a), unsquashed(a + lineDirLocal * len), climbLayout, web.alpha)
            if a.distance(to: spinnerets) > 0.5 { p.threadFrom = spinnerets }
            // Rolling over, drawn in to its middle, the silk from the
            // spinnerets runs in along its belly — under the hind feet
            // that keep it there — to where it leaves for the anchor.
            let drawnIn = smoothstep(lineGrip)
            if mode == .dangling, drawnIn > 0 {
                let via = V2.lerp(lineStance, bellyLine(Spider.lineTuck[7]), drawnIn)
                if via.distance(to: a) > 0.5 { p.threadVia = unsquashed(via) }
            }
        }
        return p
    }
}
