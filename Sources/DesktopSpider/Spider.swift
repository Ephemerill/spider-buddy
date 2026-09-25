import AppKit
import CoreGraphics

// MARK: - Configuration

struct SpiderConfig {
    var scale: CGFloat = 1.0
    var walkSpeed: CGFloat = 62          // px/s at scale 1
    var liveliness: CGFloat = 1.0        // how often it decides to do something
    var followCursor: Bool = true
    /// A pointer that fidgets close by for long enough gets stalked and
    /// pounced on. Off, it only watches.
    var pounceOnCursor: Bool = true
    /// Shooting lines: rappelling, swinging, draglines and catching a fall.
    var webs: Bool = true
    /// Spinning a hammock in a corner to rest in.
    var hammocks: Bool = true
    var paused: Bool = false
}

// MARK: - Pose handed to the renderer (all body-local unless noted)

enum Emote {
    case none, hearts, zzz, surprise, sparkle, question, note
    case exclaim        // a little burst of "!" — a nervous start
    case thought        // a thought bubble; what is in it is `SpiderPose.thought`
}

/// What is in a thought bubble.
enum Thought: Equatable {
    case heart, hungry, rain, sun, moon, music, star, bug, home
    case text(String)
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
    /// `tail` is how much loose silk trails out behind the spinnerets.
    var thread: (a: V2, b: V2, tail: CGFloat, alpha: CGFloat)?
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
    /// Windows in front of the surface it is on, in world px: whatever of
    /// the sprite falls inside them is behind them, and is not drawn.
    var hiddenBy: [CGRect] = []
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
private enum HomeGoal { case build, sleep, corner }

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
        return loop.kind == .windowEdge
    }
    var personality = Personality() {
        didSet { config.liveliness = personality.liveliness }
    }
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
        max(boutStride, speed / max(config.scale, 0.05) / Spider.maxCadence)
    }
    private static let maxCadence: CGFloat = 3.6
    private var gaitStyle: GaitStyle = .normal
    private var speedWobble = Wobble(seed: 17, freq: 0.9)
    private var liftWobble = Wobble(seed: 23, freq: 0.35)
    /// 0 = full profile, up to ~0.7 = turned three-quarters toward the viewer.
    private var glance: CGFloat = 0
    private var glanceIn: CGFloat = 4
    private var glanceUntil: CGFloat = 0
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
                                                    .groom, .legStretch, .greet, .eat, .sleep, .stretch]
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
    /// Body centre relative to the point on the line the spinnerets hold,
    /// eased so a change of side never jumps it.
    private var hangOff: V2 = .zero
    private var hangTwistPhase: CGFloat = 0
    private var hangOffFresh = true
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
    private var twirlUntil: CGFloat = 0
    /// Hand-over-hand on the line: the feet stay fixed on the thread while
    /// the body moves along it, so this advances with distance climbed.
    private var climbTravel: CGFloat = 0
    private var climbDir: CGFloat = 0
    private var prevHangLen: CGFloat = 0
    /// How far it moved along the line this frame, px, + = away from the
    /// anchor (descending); and the climbing gait's phase, in strides.
    private var hangDelta: CGFloat = 0
    private var climbPhase: CGFloat = 0
    /// Head up the line only while it is hauling itself up; otherwise it
    /// hangs head down, the way a spider on a dragline does.
    private var hangHeadUp = false
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
    private var sideSwitchFor: CGFloat = 0
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

    private let gravity = V2(0, -1950)
    /// World distance the body moves along the line per hand-over-hand cycle.
    static let climbStride: CGFloat = 18
    /// One stride of the climbing gait, in px at scale 1: how far the body
    /// travels along the line per cycle of the legs.
    static let climbStridePx: CGFloat = 30
    /// Body units travelled per gait cycle.
    private static let strideLength: CGFloat = 28
    /// Fraction of the cycle a leg spends in the air.
    private static let swingDuty: CGFloat = 0.34
    /// The hardest it can push off.
    private static let maxJumpSpeed: CGFloat = 1250
    /// How far a corner is rounded off, in points at scale 1.
    private static let cornerRadius: CGFloat = 38

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

    func scroll(_ dy: CGFloat) {
        lastUserActivity = t
        if mode == .dangling || (mode == .held && webActive) {
            webLenTarget = clamp(webLenTarget - dy * 3.2, 26, 900)
            // Being reeled about by hand: it does as it is told for a while
            // rather than deciding to jump off mid-climb.
            if webStyle == .hang { decisionIn = max(decisionIn, 3.5) }
        } else if mode == .attached, config.webs, dy < -0.5, canRappel(userAsked: true) {
            dropOnWeb()
        }
    }

    /// Single click on the body: it notices you.
    func poke() {
        wake()
        lastUserActivity = t
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
        runPendingDemo()
    }

    private func runPendingDemo() {
        guard let h = pendingDemo else { return }
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
            if let spot = bestJumpSpot(from: pos, exclude: anchor.loopID) { startJump(to: spot.point) } else { hold(.hop, 0.6) }
        case \.rappel:
            if config.webs, canRappel(userAsked: true) { dropOnWeb() } else { climbFor(h) }
        case \.swing:
            if !(config.webs && startSwing()) { climbFor(h) }
        case \.hammock: buildHammock()
        case \.nap: napInHammock()
        case \.sleep: hold(.sleep, 6)
        case \.drum: hold(.drum, 3.4); setEmote(.note, 1.4)
        case \.dance: hold(.dance, 1.8); setEmote(.note, 1.4)
        case \.roll: hold(.roll, 1.7); queue(.shake, 0.45)
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

    func celebrate() {
        wake()
        happy.velocity = 10
        setEmote(.hearts, 1.3)
        if mode == .dangling, webStyle == .hang {
            // Pleased, on a line: a twirl.
            twirlUntil = t + randRange(1.2, 1.8)
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
        // The hammock, if there is one, and it stays in it: its weight
        // sags the sling, which may take the bed down behind a window.
        if let h = hammock, h.progress >= 1, config.hammocks, !inHabitat, confine == nil,
           map.isVisible(nestCentre(h), depth: Int.max) {
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
            let score = (spot.loop.kind == .windowEdge ? 1.3 : 1) * (1.2 - off * 0.7) * randRange(0.8, 1.2)
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
            guard loop.kind == .windowEdge else { return true }
            return (map.seg(anchor).map { $0.isOpen(at: anchor.t) } ?? false) && map.isVisible(pos, depth: loop.depth)
        default: return false
        }
    }

    /// You are back: it wakes — a stretch, a shake — and comes to say hello.
    func wakeAndGreet() {
        guard dormant else { return }
        dormant = false
        greetOnWaking = true
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
        happy.velocity = 8
        setEmote(.hearts, 1.6)
        beginActivity(.greet, dur: 2.6)
        queue(.wave, 1.5)
        decisionIn = randRange(1.5, 3)
    }

    /// The charger has gone in: a jolt of excitement, even out of a nap.
    func perkUp() {
        guard !config.paused, !dormant, !inCinema, !isHeld, activity != .eat else { return }
        happy.velocity = 9
        setEmote(.sparkle, 1.2)
        guard mode == .attached else { return }
        wake()
        beginActivity(.bounce, dur: 1.0)
        queue(chance(0.5) ? .wiggle : .armsUp, 0.9)
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
    func summon(to p: V2) {
        wake()
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
        personality = d.personality
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
        SpiderDesign(name: name, look: look, personality: personality, gait: gait, habits: habits, packs: packs, customPhrases: customPhrases)
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
        updateEmote(dt: dt)
        updateBlink(dt: dt)

        if mode != .airborne { landing = nil; landingReach = 0 }
        if mode != .attached { runNose = approach(runNose, 0, 8, dt); surfacePrev = nil }
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

        headTilt.step(to: mode == .attached && activity == .watch ? 0.72 : (mode == .attached ? interestNose.value * 0.6 : 0), dt: dt)
        updateWeb(dt: dt)
        updatePrey(dt: dt)
        tidyAbandonedHammock()
        if var h = hammock, h.tickDrape(dt: dt) { hammock = h }
        rockHammock(dt: dt)
        updateLook(dt: dt)
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
        grounded.step(to: mode == .attached ? 1 : 0, dt: dt)
        bungee.step(to: 0, dt: dt)
        webAlpha.step(to: (webActive || buildThreadFrom != nil) ? 1 : 0, dt: dt)
        wagPhase += dt * (6 + wag.value * 4)

        // Volume preservation: fattening follows stretch inversely — except
        // balled up for a roll, where it pulls in all round.
        let s = stretch.value
        fatten.value = lerp(fatten.value, curled ? 1.0 : 1 / max(0.6, s), 0.35)

        updateRope(dt: dt)
        updateKnees(dt: dt)
    }

    // MARK: The laser dot

    /// A red dot to chase. Set while the pointer is down in laser mode.
    var laser: V2? {
        didSet {
            if laser != nil, oldValue == nil {
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
                beginActivity(chance(0.5) ? .hop : .peer, dur: chance(0.5) ? 0.42 : 0.8)
                if chance(0.4) { setEmote(.sparkle, 0.7) }
            } else {
                beginActivity(.curious, dur: randRange(0.4, 0.8))
            }
            return
        }
        if off < 40 * sc || (abs(along) > off * 2 && abs(along) < 260 * sc) {
            // Near this edge: run for it.
            let dir: CGFloat = along >= 0 ? 1 : -1
            if dir != walkDir { walkDir = dir; facing = dir }
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
            if dir != walkDir { walkDir = dir; facing = dir }
            beginActivity(.scurry, dur: randRange(0.5, 1.2))
        }
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
        if dir != walkDir { walkDir = dir; facing = dir }
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
              homing == nil, build == nil, peek == nil, t > escapeUntil, t >= bedBoundUntil,
              !(confined && !inBox), !hangOnly else { return true }
        if [.sleep, .eat, .watch, .peekaboo, .roll, .spin, .crouch, .shoot, .fasten, .scurry,
            .startle, .stretch, .shake, .bounce, .dance, .drum].contains(activity) { return true }
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
        let focus = noticing ? commotionAt : cursor
        let wants = noticing || config.followCursor && !busy && !bored && d < Spider.interestRange * sc && inBoxOrFree(cursor)
            && t - lastUserActivity < 8 && cursorHunt == .none
        interest = approach(interest, wants ? 1 : 0, wants ? 6.0 : (busy ? 4 : 1.2), dt)
        // Where the pointer is, give or take its fidgeting: what a pounce
        // is aimed at.
        cursorCentre = approach(cursorCentre, cursor, 7, dt)
        var nose: CGFloat = 0
        if interest > 0.01, mode == .attached {
            // Body-local: +x is the way it faces along the ledge, +y away
            // from the surface. The head tips up or down toward the pointer.
            let l = toLocalDir(focus - pos)
            nose = clamp(atan2(l.y, max(abs(l.x), 12 * sc)), -0.8, 0.8)
            nose *= SpiderRenderer.profileAmount(yaw: yaw)
            // The body turns to point at the pointer, continuously: the yaw
            // is the cosine of the pointer's bearing along the ledge, so
            // ahead is profile, straight above is face on, and behind is
            // the other profile — no stepping between fixed views. Ahead it
            // stops just short of full profile so a little face still shows.
            // On the move it only comes three-quarters round, so it
            // never walks backwards.
            //
            // The eyes follow the pointer at once; the body comes after on
            // a smoothed bearing, and only turns right round to the other
            // side once the pointer has stayed well round there — so a
            // pointer passing back and forth over it does not have it
            // swinging from one profile to the other and back every pass,
            // and a gesture already under way finishes on the side it began.
            let a = (focus - pos).rotated(by: -heading)
            var c = a.x / max(a.length, 1)
            if speed > 1 || [.walk, .scurry, .sneak].contains(activity) { c = facing * max(facing * c, 0.45) }
            interestBearing = approach(interestBearing, c, 2.4, dt)
            let gesturing = Spider.gestures.contains(activity) || activity == .stare
            if interestBearing * interestSide < -0.3, !gesturing {
                sideSwitchFor += dt
                if sideSwitchFor > 0.5 { interestSide = -interestSide; sideSwitchFor = 0 }
            } else {
                sideSwitchFor = max(0, sideSwitchFor - dt * 2)
            }
            interestYawTarget = interestSide * max(interestSide * interestBearing, 0.12) * 0.88
        }
        if interest < 0.05 {
            // Not following anything: start from however it stands.
            interestSide = facing
            interestBearing = yaw
            sideSwitchFor = 0
        }
        interestNose.step(to: nose * interest, dt: dt)

        // An aimless walk is dropped for a better look.
        if interest > 0.75, activity == .walk, activityTime > 0.5, walkPauseAt > 90 || activityTime < walkPauseAt,
           chance(dt * 1.2) {
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
              inBoxOrFree(cursor), chance(dt * 2.5) else { return }
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
        if dist > 460 * sc || t - cursorHuntSince > 14 || !inBoxOrFree(cursor) || inCinema
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
        if !map.isOnScreen(cursor, slack: 20) || cursor.distance(to: pos) > 400 * sc || !inBoxOrFree(cursor) {
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
        } else if roll < 0.55 {
            thinkSomething()
        } else if roll < 0.7, t - lastUserActivity < 20 {
            think(P.affection > 0.5 ? .heart : .star)
        } else if roll < 0.8 {
            think([.rain, .sun, .moon, .music, .bug, .home].randomElement()!)
        }
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

    // MARK: Peek-a-boo

    /// Edges to hide behind on the segment it is on: where a window in
    /// front of its surface crosses the segment. `into` is the direction
    /// along the segment that leads behind the window.
    private func hidingEdges() -> [(t: CGFloat, into: CGFloat)] {
        // Only a window's edge can be behind another window; on the screen's
        // rim it is always in front, so there is nothing there to hide behind.
        guard mode == .attached, let loop = map.loop(anchor.loopID), loop.kind == .windowEdge,
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
        if let b = best { startJump(to: b.point) } else { turnTo(chance(0.5) ? 1 : -1, then: .walk, for: randRange(1.5, 3)) }
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
        let popT = pk.edgeT - pk.into * 24 * sc           // out, most of it clear of the edge
        let brinkT = pk.edgeT - pk.into * 22 * sc         // nose at the edge
        var goal: CGFloat
        var pace: CGFloat
        switch pk.stage {
        case 0: goal = brinkT; pace = config.walkSpeed * 0.6
        case 1: goal = hideT; pace = config.walkSpeed * 0.9
        case 3: goal = popT; pace = config.walkSpeed * 2.6
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

    /// How far it is along a loop from here to `target` going `dir`, or nil
    /// if a blocked stretch (a window in front) is in the way.
    private func loopDistance(_ loop: SurfaceLoop, to target: Anchor, dir: CGFloat) -> CGFloat? {
        let n = loop.segs.count
        guard target.segIdx < n, anchor.segIdx < n else { return nil }
        var idx = anchor.segIdx
        var t = anchor.t
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
        pos = a + V2(0, -18 * config.scale)
        vel = .zero
        heading = -.pi / 2
        headingTarget = heading
        headingVel = 0
        attachWeb(at: a)
        webStyle = .hang
        webLen = 18 * config.scale
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
        for p in prey { p.pos += d }
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
    func release(_ kind: PreyKind) -> Prey {
        let screen = confine ?? map.screenFrame(containing: pos)
        var at: V2
        if kind.flies {
            at = V2(clamp(pos.x + randRange(-380, 380), screen.minX + 80, screen.maxX - 80),
                    clamp(pos.y + randRange(120, 300), screen.minY + 80, screen.maxY - 80))
        } else {
            // A ledge facing up, in the open, a decent distance away.
            var best: (score: CGFloat, point: V2)?
            for spot in map.sampleSpots(spacing: 40) where spot.seg.facing == .up && screen.contains(spot.point.point) {
                let d = spot.point.distance(to: pos)
                guard d > 160, spot.seg.isOpen(at: spot.anchor.t) else { continue }
                let score = remap(d, 160, 700, 1.2, 0.6) * spot.loop.kind.appeal * randRange(0.7, 1.3)
                if best == nil || score > best!.score { best = (score, spot.point) }
            }
            at = best?.point ?? V2(clamp(pos.x + randRange(-300, 300), screen.minX + 80, screen.maxX - 80), screen.minY + 60)
            at.y += 30   // dropped in from a little way up
        }
        let p = Prey(kind: kind, id: nextPreyID, at: at, scale: config.scale)
        p.home = confine
        nextPreyID += 1
        prey.append(p)
        wake()
        if mode == .attached, [.rest, .sleep, .idle, .look].contains(activity) {
            decisionIn = min(decisionIn, 0.3)
        }
        setEmote(.question, 0.8)
        return p
    }

    /// The creature under the pointer, if any, for picking up.
    func preyHit(_ p: V2) -> Prey? {
        prey.first { $0.state == .loose && $0.pos.distance(to: p) < 22 * $0.scale + 6 }
    }

    func beginPreyGrab(_ p: Prey, at point: V2) {
        p.held = true
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

    /// Whatever it is after: the nearest thing still loose.
    private func quarry() -> Prey? {
        guard t > huntPauseUntil, !inCinema else { return nil }
        if let id = huntTarget, let p = prey.first(where: { $0.id == id && $0.state == .loose }) { return p }
        let loose = prey.filter { $0.state == .loose }
        guard let nearest = loose.min(by: { $0.pos.distance(to: pos) < $1.pos.distance(to: pos) }) else { return nil }
        huntTarget = nearest.id
        huntSince = t
        return nearest
    }

    private func updatePrey(dt: CGFloat) {
        for p in prey { p.update(dt: dt, t: t, map: map, spider: pos) }
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
        prey.removeAll { $0.state == .eaten && $0.alpha <= 0 }
        fed = max(0, fed - dt / 900)
        // Lost track of it for too long: leave it be for a while.
        if huntTarget != nil, t - huntSince > 150 {
            huntTarget = nil
            huntPauseUntil = t + 12
        }
    }

    /// The hunt, one decision at a time: close in along its own ledge,
    /// stalking the last stretch, and pounce; or leap to wherever it can get
    /// nearest to; a fly in the air is snatched when it comes within range.
    private func hunt(_ p: Prey) {
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

        if p.kind.flies, !p.onSurface {
            // In the air: snatch it if it comes near enough, otherwise keep
            // under it, watching.
            let lead = p.pos + p.vel * 0.22
            if dist < 230 * sc, t - lastPounceAt > 1.2, ballistic(from: pos, to: lead) != nil {
                pounce(at: lead)
            } else if abs(along) > 80 {
                turnTo(along >= 0 ? 1 : -1, then: .walk, for: clamp(abs(along) / max(config.walkSpeed, 1), 0.4, 2.0))
            } else {
                beginActivity(.look, dur: randRange(0.5, 1.1))
            }
            return
        }

        let sameEdge = p.anchor?.loopID == anchor.loopID && p.anchor?.segIdx == anchor.segIdx
        if sameEdge || (off < 30 * sc && abs(along) < 140 * sc) {
            let settled = p.onSurface && p.vel.length < 20
            if dist < 14 * sc {
                catchPrey(p)
            } else if abs(along) < 75 * sc, facingIt, settled, t - lastPounceAt > 1.2 {
                // Close, facing it, and it is sitting still: pounce.
                pounce(at: p.mouthPoint)
            } else if abs(along) < 75 * sc, facingIt {
                // It is on the move: wait, poised, for it to settle.
                beginActivity(.crouch, dur: randRange(0.3, 0.6))
                pendingJump = nil
            } else {
                // Close in: a sneak for the last stretch, a walk before that.
                let dir: CGFloat = along >= 0 ? 1 : -1
                let style: Activity = abs(along) < 230 * sc ? .sneak : .walk
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
        if let b = best, stalled || abs(along) < 260 * sc || chance(0.5) {
            startJump(to: b.point)
            huntStalls = 0
        } else {
            walkToward(p.pos)
        }
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

    private func pounce(at point: V2) {
        lastPounceAt = t
        huntPounce = true
        pounceMark = point
        pendingJump = point
        beginActivity(.crouch, dur: randRange(0.28, 0.42))
    }

    private func catchPrey(_ p: Prey) {
        guard p.state == .loose else { return }
        p.state = .caught
        caught = p
        huntTarget = nil
        huntPounce = false
        happy.velocity = 6
        setEmote(.sparkle, 0.8)
        if mode == .attached {
            queued = nil
            beginActivity(.eat, dur: p.kind.mealTime * randRange(0.9, 1.15))
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
        c.state = .eaten
        c.eaten = 1
        caught = nil
        fed = min(1, fed + c.kind.nourishment)
        happy.velocity = 9
        setEmote(.hearts, 1.6)
        queue(.wiggle, randRange(0.8, 1.3))
    }

    // MARK: Silk line

    /// Where the silk leaves the body, in sprite units: the spinnerets when
    /// it hangs in line with the thread, the top of the abdomen when it is
    /// slung under a swing.
    private func silkAttachLocal() -> V2 {
        let ab = SpiderRenderer.abdomen(for: look)
        // On a line, or shooting one in mid-air with its rear brought
        // round to the mark: the spinnerets at the tip of the abdomen.
        if mode == .dangling || (mode == .airborne && (airShot != nil || draglineCatchY != nil)) {
            return V2(ab.c.x - ab.rx + 3, ab.c.y)
        }
        return V2(ab.c.x, ab.c.y + ab.ry - 2)
    }

    private func silkAttachWorld() -> V2 {
        toWorld(silkAttachLocal())
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
        rope.step(head: h, tail: attach, gravity: g, drag: rope.tailPinned ? 0.975 : 0.985, dt: dt)
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
            }
        } else if mode == .dangling && webStyle == .swing {
            yaw = approach(yaw, facing, 9, dt)
        } else if mode == .dangling {
            if t < twirlUntil {
                // A twirl whips it right round, several times.
                yaw = approach(yaw, cos(t * 4.5), 14, dt)
                facing = yaw >= 0 ? 1 : -1
            } else {
                // Turning slowly on the line: it comes part-way round to
                // show its face, and drifts back — never right round to
                // the other side, which on a thread is a roll of the whole
                // body and reads as a spin for no reason.
                let toward = 0.58 + 0.42 * cos(t * 0.45 + hangTwistPhase)
                yaw = approach(yaw, facing * toward, 3, dt)
            }
        } else if mode == .nesting {
            yaw = approach(yaw, facing, 6, dt)
        } else if mode == .airborne, airShot != nil || draglineCatchY != nil {
            // Side on for the shot and the line, so the twist reads.
            yaw = approach(yaw, facing, 12, dt)
        } else if mode == .attached && (activity == .greet || activity == .stare
                                        || (liftsOuterPair && (activity == .armsUp || activity == .curious))) {
            // (A two-legged gesture begun face on stays face on: the legs it
            // raised are the ones either side of its face.)
            // Square on to you, all but the whole way round to the front
            // view — not right on it, where the spring's overshoot would
            // tip it over into the mirror image and back.
            yawSpring(to: facing * 0.1, dt: dt)
        } else {
            // A glance turns it part-way toward you without changing which
            // way it faces along the ledge. (Only on a ledge: a glance it
            // was in the middle of when it was picked up does not follow
            // it into the air.)
            let g = activity == .glance ? 0.62 : (mode == .attached ? glance : 0)
            var target = facing * (1 - g)
            // Interested, it turns toward the pointer instead — the whole
            // way round if need be, on the same spring.
            if mode == .attached { target = lerp(target, interestYawTarget, interest) }
            yawSpring(to: target, dt: dt)
        }
        if mode != .attached || activity == .turn { yawVel = 0 }
        if (yaw >= 0) != (before >= 0) {
            // Come round past the front view after the pointer, not in a
            // turn: it now faces the other way along the ledge, and stays
            // that way when the pointer leaves.
            if mode == .attached, activity != .turn {
                facing = yaw >= 0 ? 1 : -1
                walkDir = facing
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
            }
        }
    }

    private var mirrorSign: CGFloat { yaw >= 0 ? 1 : -1 }

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
        if mode == .nesting, let h = hammock {
            // On the silk: the sling's centre line is the ground.
            return toLocal(h.nearest(to: toWorld(local)))
        }
        guard mode == .attached, let loop = map.loop(anchor.loopID), !loop.edge.isEmpty else { return local }
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
                if other.kind == .windowEdge, other.rect.insetBy(dx: -reach - 40, dy: -reach - 40).contains(want.point) == false { continue }
                let o = footOnEdge(want, other, wrap: false)
                guard o.visible else { continue }
                let cost = want.distance(to: o.point) + 3 * config.scale
                if cost < bestCost, cost < reach { best = o.point; bestCost = cost }
            }
        }
        return toLocal(best)
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
        let visible = loop.kind != .windowEdge || map.isVisible(point + normal * 3, depth: loop.depth)
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
        let visible = loop.kind != .windowEdge || map.isVisible(point + normal * 3, depth: loop.depth)
        return (point, visible)
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
        return groundFoot(target, spread: true)
    }

    private func trackCursorMotion(dt: CGFloat) {
        let d = cursor - prevCursor
        prevCursor = cursor
        if dt > 0 { cursorVel = approach(cursorVel, d / dt, 18, dt) }

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
        // (Not while it has the pointer marked as prey: that is not a pet.)
        if pettingScore > 0.85, cursorHunt == .none {
            happy.value = max(happy.value, 0.85)
            if emote == .none { setEmote(.hearts, 1.0) }
            if mode == .attached, gestureReady, activity != .wiggle, activity != .dance, chance(dt * 1.5) {
                beginActivity(chance(0.6) || lastGesture == .dance ? .wiggle : .dance, dur: 0.9)
            }
            wake()
        }
    }

    // MARK: Attached

    private func updateAttached(dt: CGFloat) {
        guard let here = map.resolve(anchor, cornerRadius: Spider.cornerRadius * config.scale),
              let loop = map.loop(anchor.loopID) else {
            detachAndFall()
            return
        }

        surfaceMotion = surfacePrev.map { here.pos - $0 } ?? .zero
        surfacePrev = here.pos

        // Safety nets. A window that jumps a long way in one poll has gone
        // somewhere we cannot follow (another Space, another display), and a
        // walk that goes nowhere means the surface under it is not what we
        // think it is. Either way, let go rather than pace in mid-air.
        if loop.kind == .windowEdge {
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
        // On a hunt nothing else is allowed to run long: a walk toward the
        // prey is re-aimed every second or so, and idle habits are dropped.
        if laser != nil, !inCinema, [.walk, .sneak, .rest, .sleep, .watch, .stare, .groom, .look, .glance, .drum, .eat].contains(activity) {
            if activityTime > 0.4 { queued = nil; finishActivity() }
        }
        if departing != nil, ![.walk, .turn, .crouch, .shoot, .fasten, .idle].contains(activity), activityTime > 0.4 {
            queued = nil
            finishActivity()
        }
        if friendChase != nil || friendFlee != nil, !inCinema, [.walk, .sneak, .rest, .sleep, .watch, .stare, .groom, .look, .glance, .drum, .fidget, .scratch, .peer].contains(activity) {
            if activityTime > 0.6 { queued = nil; finishActivity() }
        }
        if caught == nil, huntTarget != nil, prey.contains(where: { $0.id == huntTarget && $0.state == .loose }) {
            let hunting: Set<Activity> = [.walk, .sneak, .scurry, .look, .turn, .crouch, .idle, .startle, .shake]
            if !hunting.contains(activity) { queued = nil; finishActivity() }
            else if [.walk, .sneak, .scurry].contains(activity), activityTime > 1.0 { activityDur = min(activityDur, activityTime) }
        }
        // Stalking the pointer: the same, with the creep re-aimed often.
        if cursorHunt == .stalking {
            let stalking: Set<Activity> = [.walk, .sneak, .scurry, .look, .turn, .crouch, .idle, .startle, .shake, .stare]
            if !stalking.contains(activity) { queued = nil; finishActivity() }
            else if [.walk, .sneak].contains(activity), activityTime > 0.9 { activityDur = min(activityDur, activityTime) }
        }
        if activityTime > activityDur { finishActivity() }
        // Put to bed while you are away: whatever roused it, back to sleep.
        if dormant, activity != .sleep { fallAsleep() }
        if activity == .idle && decisionIn <= 0 { think() }

        // Something has slid in front of where it is standing, or it has been
        // pushed off the screen: get out of the way.
        // Only a window's edge can be covered; the screen's rim, the menu
        // bar and the Dock are always its to walk, whatever overlaps them.
        let onWindow = loop.kind == .windowEdge && activity != .peekaboo && !calmUnderCover
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
        targetSpeed = config.walkSpeed * post.speed * bout
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
        if activity == .roll {
            lift.value = approach(lift.value, post.lift * config.scale, 40, dt); lift.velocity = 0
        } else if lift.value < -maxSink(tilt: angleDelta(here.tangent.angle, heading)) {
            // However hard it comes down, the belly never goes into the
            // ledge: the legs bottom out.
            lift.value = -maxSink(tilt: angleDelta(here.tangent.angle, heading))
            lift.velocity = max(lift.velocity, 0)
        }
        skid.step(to: 0, dt: dt)
        skid.value = clamp(skid.value, -8 * config.scale, 8 * config.scale)
        pitch.step(to: post.pitch + interestNose.value * 0.3, dt: dt)
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
        let bobAmp = speedFrac * 1.0 * boutBob * config.scale * (activity == .roll ? 0 : 1)
        let bob = sin(gaitPhase * 4 * .pi) * bobAmp * 0.5 + sin(gaitPhase * 2 * .pi) * bobAmp * 0.3
        let sway = cos(gaitPhase * 2 * .pi) * bobAmp * 0.3
        let breathe = bodyWobble.value(t * (activity == .sleep ? 0.6 : 1.0))
            * (activity == .sleep || activity == .rest ? 1.1 : 0.45) * config.scale
        // Interested, it leans along the ledge toward the pointer: the body
        // shifts and the planted feet stay put.
        let toward = clamp((cursor - pos).dot(here.tangent) / (90 * config.scale), -1, 1)
        interestLean.step(to: toward * interest * 4 * config.scale * SpiderRenderer.profileAmount(yaw: yaw), dt: dt)
        pos = anchorPos + here.normal * (bob + lift.value + breathe) + here.tangent * (sway + interestLean.value + skid.value)

        // Every so often it looks over at you — a three-quarter turn of the
        // body, briefly, even mid-walk.
        glanceIn -= dt
        if glanceIn <= 0 {
            glanceIn = randRange(3, 9) / lerp(0.4, 1.8, personality.affection)
            if glance == 0, [.walk, .idle, .look, .rest].contains(activity) {
                glance = randRange(0.3, 0.55)
                glanceUntil = t + randRange(0.7, 1.6)
            }
        }
        if glance > 0, t > glanceUntil { glance = 0 }

        reactToCursor(dt: dt)
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
                p.lift = 0.5
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
            let hops = 3.0
            p.lift = abs(sin(u * .pi * hops)) * 8
            p.legsFree = p.lift > 2
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
            // A small nervous hop straight up and down, legs tucked at the top.
            let h = sin(clamp(u, 0, 1) * .pi)
            p.lift = h * 7
            p.legsFree = h > 0.35
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
        }
        // Standing, it is never quite still: a slow shift of weight.
        if p.speed == 0 && activity != .sleep && activity != .roll {
            p.lift += liftWobble.value(t) * 0.8
        }
        // How it carries itself: low and flat, or up on its toes.
        if activity != .sleep && activity != .rest && activity != .roll && activity != .crouch {
            p.lift += gait.liftOffset
        }
        return p
    }

    /// Mid-activity events: the flip in a turn, the shake's wobble, and so on.
    private func progressActivity(dt: CGFloat) {
        switch activity {
        case .turn:
            break   // the flip happens in updateYaw, as it passes the front view
        case .shake:
            // A rapid wobble that dies away.
            let decay = max(0, 1 - activityTime / activityDur)
            headingVel += sin(activityTime * 62) * 6 * decay
            wag.value = decay * 1.2
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
        case .eat:
            let u = clamp(activityTime / max(activityDur, 0.1), 0, 1)
            caught?.eaten = easeInOutSine(u) * 0.9
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
        walkThen = nil
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
        if a == .sleep { setEmote(.zzz, dur) }
        if a == .wiggle && emote == .none { setEmote(.note, min(dur, 1.0)) }
        if a == .walk {
            // A first pause a little way in, on longer walks; none on a
            // short one, and none when it is going somewhere on purpose.
            let purposeful = huntTarget != nil || laser != nil || homing != nil || build != nil || inCinema || t < bedBoundUntil || (confined && !inBox) || cursorHunt != .none
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

    private func advanceAlong(loop: SurfaceLoop, dt: CGFloat) {
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
            guard canContinue else { reachedEnd = true; speed = 0; break }
            let wrapped = (nextIdx + n) % n
            let next = loop.segs[wrapped]
            let entryT: CGFloat = walkDir > 0 ? 0 : next.len
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

    // MARK: Cursor reactions

    private func reactToCursor(dt: CGFloat) {
        guard config.followCursor, !inCinema, cursorHunt == .none else { return }
        let d = cursor.distance(to: pos)
        let busy = [.startle, .crouch, .turn, .sleep, .curious, .stretch, .shake, .roll, .spin, .armsUp, .shoot].contains(activity)

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

    // MARK: - Decisions

    private func think() {
        decisionIn = randRange(1.0, 3.4) / max(config.liveliness, 0.25)
        let idleFor = t - lastUserActivity
        let dCursor = cursor.distance(to: pos)
        let P = personality

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

        // Holding a meal it has not got round to: eat it.
        if let c = caught, c.state == .caught {
            beginActivity(.eat, dur: c.kind.mealTime * randRange(0.9, 1.15))
            return
        }
        // Something to eat about: everything else can wait.
        if caught == nil, !inCinema, let q = quarry() {
            decisionIn = randRange(0.25, 0.7) / max(config.liveliness, 0.25)
            hunt(q)
            return
        }

        // Left alone, it settles down and eventually nods off. The lazy ones
        // do not wait to be left alone — and if it has a hammock, that is
        // where it goes.
        if idleFor > lerp(120, 20, P.laziness) * lerp(1, 0.35, drowsy) || habits.sleep >= 0.995,
           chance(min(1, lerp(0.1, 0.6, P.laziness) * lerp(1, 1.8, drowsy) * hw(\.sleep))) {
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

        if config.followCursor, dCursor < 340, inBoxOrFree(cursor), chance(min(1, lerp(0.1, 0.65, P.curiosity) * hw(\.approach))) {
            // Investigate the pointer — from where it stands, if it is
            // already close enough to have its attention.
            if dCursor > 70, interest < 0.5 {
                walkToward(cursor)
            } else {
                beginActivity(.look, dur: randRange(0.8, 2.0))
            }
            return
        }

        // Someone is about and there is a window edge to hide behind nearby:
        // peek-a-boo, now and then (or as soon as it can if it was asked to).
        let asked = t < wantsPeekabooUntil
        if asked || (config.followCursor && dCursor < 520 && t - lastUserActivity < 20
                     && chance(min(1, lerp(0.03, 0.14, P.playfulness) * hw(\.peekaboo)))) {
            if startPeekaboo(reach: asked ? 600 : 260) { wantsPeekabooUntil = -1; return }
            if asked { goHideSomewhere() ; return }
        }

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
        options.append((30 * busy * hw(\.wander), {
            let dir: CGFloat = chance(0.7) ? self.walkDir : -self.walkDir
            let sneaky = lerp(0.3, 0.05, P.bravery)
            let hurried = lerp(0.04, 0.22, P.energy) * lerp(1, 0.2, self.drowsy)
            let style: Activity = chance(sneaky) ? .sneak : (chance(hurried) ? .scurry : .walk)
            let dur = style == .scurry ? randRange(0.5, 1.2) : randRange(1.4, 5.0)
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
        options.append((10 * hw(\.look), { self.beginActivity(.look, dur: randRange(0.7, 2.2)) }))
        options.append((6 * lazy * hw(\.rest), { self.beginActivity(.rest, dur: randRange(3, 8)) }))
        options.append((6 * hw(\.groom), { self.beginActivity(.groom, dur: randRange(1.4, 2.8)) }))
        options.append((6 * (0.5 + busy * 0.5) * hw(\.fidget), { self.beginActivity(.fidget, dur: randRange(0.7, 1.2)) }))
        options.append((4 * hw(\.scratch), { self.beginActivity(.scratch, dur: randRange(1.0, 1.6)) }))
        options.append((2 * love * hw(\.wave) * gestureWeight(.wave), {
            self.beginActivity(.wave, dur: 1.5)
            self.happy.velocity = 4
        }))
        options.append((2 * play * hw(\.wiggle) * gestureWeight(.wiggle), { self.beginActivity(.wiggle, dur: 0.8) }))
        options.append((3 * love * hw(\.glance), { self.beginActivity(.glance, dur: randRange(0.8, 1.6)) }))
        if config.followCursor, dCursor < 520, t - lastUserActivity < 30 {
            options.append((3 * love * hw(\.greet) * gestureWeight(.greet), {
                self.beginActivity(.greet, dur: randRange(1.8, 2.6))
                if chance(0.5) { self.setEmote(.hearts, 1.0) }
            }))
        }
        // Sitting still, turned to face you, just watching.
        if config.followCursor, dCursor < 560, t - lastUserActivity < 40 {
            options.append((3 * love * lerp(0.6, 1.4, P.curiosity) * hw(\.stare), {
                self.beginActivity(.stare, dur: randRange(3, 7))
            }))
        }
        // A thought, now and then.
        options.append((4 * lerp(0.5, 1.5, P.curiosity) * (raining ? 1.8 : 1) * hw(\.muse), { self.museIfSoMoved(); if self.emote == .none { self.beginActivity(.look, dur: randRange(0.6, 1.2)) } }))

        // Drumming on whatever it is standing on, the way a jumping spider
        // signals: a few bursts of quick taps with its front legs.
        options.append((2.5 * play * lerp(0.6, 1.4, P.energy) * hw(\.drum), {
            self.beginActivity(.drum, dur: randRange(2.9, 5.8))
            self.setEmote(.note, 1.4)
        }))
        options.append((3 * lerp(0.4, 1.8, P.curiosity) * hw(\.peer), { self.beginActivity(.peer, dur: randRange(1.2, 2.0)) }))
        options.append((2.5 * lerp(0.5, 1.5, (P.affection + P.bravery) / 2) * hw(\.armsUp) * gestureWeight(.armsUp), {
            self.beginActivity(.armsUp, dur: randRange(0.9, 1.5))
            if chance(0.5) { self.setEmote(.sparkle, 0.9) }
        }))
        options.append((2 * play * hw(\.roll), {
            self.beginActivity(.roll, dur: randRange(1.5, 1.9))
            self.queue(.shake, 0.45)
        }))
        options.append((1.5 * play * hw(\.dance) * gestureWeight(.dance), {
            self.beginActivity(.dance, dur: randRange(1.2, 2.0))
            self.setEmote(.note, 1.4)
        }))
        options.append((1.5 * busy * hw(\.pushup), { self.beginActivity(.pushup, dur: randRange(1.2, 1.8)) }))
        options.append((1.5 * (0.5 + lazy * 0.5) * hw(\.stretch), { self.beginActivity(.legStretch, dur: 1.6) }))
        options.append((1 * play * hw(\.spin), { self.beginActivity(.spin, dur: 0.1) }))
        options.append((2 * hw(\.look), { self.turnTo(-self.walkDir, then: .look, for: randRange(0.6, 1.4)) }))
        if surfaceNormal.y < -0.5 {
            // Hanging under something is no place to linger: let go and
            // drop onto whatever is below.
            options.append((14, { if !self.dropOffUnderside() { self.turnTo(-self.walkDir, then: .walk, for: randRange(1.2, 3.0)) } }))
        }
        options.append((8 * hw(\.leap) * chill, {
            if let spot = self.bestJumpSpot(from: self.pos, exclude: self.anchor.loopID) {
                self.startJump(to: spot.point)
            } else {
                self.turnTo(chance(0.5) ? 1 : -1, then: .walk, for: randRange(1.2, 3.0))
            }
        }))
        options.append((8 * hw(\.rappel) * chill, {
            if self.config.webs, self.canRappel() {
                self.dropOnWeb()
            } else {
                self.beginActivity(.walk, dur: randRange(1.2, 3.0))
            }
        }))
        // Swinging off on a line, if there is something up ahead to hang it
        // from — not in a box, where there is no room for it.
        if !confined {
            options.append((7 * hw(\.swing) * lerp(0.6, 1.4, P.playfulness), {
                if self.config.webs, self.startSwing() { return }
                self.beginActivity(.look, dur: randRange(0.6, 1.2))
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
        // A hammock left half-spun: back to finish it, before long.
        if let h = hammock, h.progress < 1, config.hammocks, !confined {
            options.append((12 * hw(\.hammock), { self.goHome(.build) }))
        }
        draw(options)
    }

    /// The multiplier one of its habit dials puts on a weight.
    private func hw(_ habit: KeyPath<Habits, CGFloat>) -> CGFloat { Habits.weight(habits[keyPath: habit]) }

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
            return
        }
        // Hanging under something and aiming below: it lets go and drops,
        // with a push away from the surface, rather than leaping into it —
        // unless the surface is glass it means to go through.
        if !glassLeap, launch.length < 1 || launch.normalized.dot(surfaceNormal) < -0.05 {
            let along = launch - surfaceNormal * launch.dot(surfaceNormal)
            launch = along.clampedLength(220) + surfaceNormal * 90
        }
        glassLeap = false
        pendingJump = nil
        launchLoop = anchor.loopID
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
        crouch.velocity = -9
        stretch.velocity = 5
        wag.reset(0)
        legMode = .free
    }

    /// Launch velocity that actually lands on `p1`, or nil if it is out of
    /// range. Picks the flattest arc the spider has the legs for, just above
    /// the minimum-energy solution — so a jump either looks like a jump or is
    /// never attempted.
    private func ballistic(from p0: V2, to p1: V2) -> V2? {
        let d = p1 - p0
        let g = -gravity.y
        let r = d.length
        guard r > 1 else { return nil }
        let vMin = (g * (d.y + r)).squareRoot()
        guard vMin.isFinite, vMin <= Spider.maxJumpSpeed else { return nil }
        let v = min(vMin * 1.06, Spider.maxJumpSpeed)
        if abs(d.x) < 1 { return V2(0, v) }
        let dx = abs(d.x)
        let v2 = v * v
        let disc = max(0, v2 * v2 - g * (g * dx * dx + 2 * d.y * v2))
        let theta = atan((v2 - disc.squareRoot()) / (g * dx))
        let dir = V2(cos(theta) * (d.x >= 0 ? 1 : -1), sin(theta))
        return dir * v
    }

    private func bestJumpSpot(from p: V2, exclude: String) -> (anchor: Anchor, point: V2)? {
        let spots = map.sampleSpots(spacing: 40)
        guard !spots.isEmpty else { return nil }
        var scored: [(CGFloat, Anchor, V2)] = []
        let playful = config.followCursor && cursor.distance(to: p) < 700
        let normal = surfaceNormal
        for s in spots {
            let d = s.point.distance(to: p)
            // A short hop straight down onto something below counts too —
            // that is how it gets off the underside of a low window.
            let below = s.point.y < p.y - 20 && abs(s.point.x - p.x) < 60
            guard d > (below ? 28 : 70), d < 680 else { continue }
            var score = s.loop.kind.appeal
            score *= remap(d, 70, 680, 1.25, 0.45)
            if let box = confine, !box.contains(s.point.point) { score *= 0.03 }
            if s.loop.id == exclude { score *= 0.18 }
            if s.loop.id == anchor.loopID { score *= 0.3 }
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
            facing = vel.x >= 0 ? 1 : -1
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
        let impact = min(vel.length, 1400)
        hurrying = false
        mode = .attached
        anchor = a
        lastLoopRect = nil
        walkDir = vel.dot(seg.dir) >= 0 ? 1 : -1
        // Coming straight down onto it, it keeps facing the way it already
        // does rather than flipping round as it lands.
        if abs(vel.dot(seg.dir)) < 20 {
            let forward = V2.angle(heading) * facing
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
        legFramePos = pos
        legFrameHeading = heading
        vel = .zero
        speed = 0
        // Stand on the ledge, facing the way it was going. The heading is left
        // to its spring, so the body swings down onto the surface rather than
        // snapping to it; the planted feet hold the ledge under the swing.
        headingTarget = seg.angle
        facing = walkDir
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
            let spot = groundFoot(legs[i].rest, spread: true)
            let foot = toWorld(legs[i].foot)
            let through = map.snapToEdge(foot, loopID: a.loopID).map { (foot - $0).dot(normal) < 1 } ?? false
            if through {
                legs[i].foot = spot
                legs[i].settle = -1
            } else {
                legs[i].settle = 0
                legs[i].swingFrom = legs[i].foot
                legs[i].settleTo = spot
            }
        }
        detachWeb(fade: true)
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
            if caught == nil { decisionIn = 0.15 }
        }
        if cursorHunt == .pouncing {
            // Missed the pointer: a look about for where it went, and it
            // may try again soon.
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
            beginActivity(.eat, dur: c.kind.mealTime * randRange(0.9, 1.15))
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
        guard loop.kind != .windowEdge || map.isVisible(point, depth: loop.depth) else { return nil }
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
        attachWeb(at: anchor)
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
            var off = silkAttachLocal()
            off.x *= mirrorSign
            hangOff = -off.rotated(by: heading) * config.scale
            hangOffFresh = false
            let r = (pos - hangOff) - webAnchor
            if r.length > 4 {
                webLen = max(20, r.length - bungee.value)
                webAngle = atan2(r.x, -r.y)
            }
            prevHangLen = webLen + bungee.value
        }

        // Keep the pendulum on the display: never pay out more thread than
        // there is room below the anchor, and never swing so wide it leaves
        // the sides.
        let screen = map.screenFrame(containing: webAnchor)
        let margin = 30 * config.scale
        var maxLen = max(40, webAnchor.y - (screen.minY + margin))
        if hangOnly, let box = confine { maxLen = min(maxLen, max(40, webAnchor.y - (box.minY + margin))) }
        webLenTarget = min(webLenTarget, maxLen)
        let swinging = webStyle == .swing
        if swinging {
            // A swing from low down starts on a line longer than the anchor
            // is high; it is what keeps the body off the floor *at this
            // angle* that bounds it, so the line is hauled in gradually as
            // it comes down through the arc, never snapped short.
            webLen = min(webLen, maxLen / max(cos(webAngle), 0.25))
        } else {
            webLen = min(webLen, maxLen)
        }

        let maxSwing: CGFloat = swinging ? 1.5 : 1.1
        // Past the widest it can swing, it is eased back rather than
        // bounced: a hard reversal here is what a jolt looks like.
        var limitAcc: CGFloat = 0
        if abs(webAngle) > maxSwing {
            let over = abs(webAngle) - maxSwing
            limitAcc = -(webAngle > 0 ? 1 : -1) * over * 60 - webAngleVel * 3
            webAngle = clamp(webAngle, -(maxSwing + 0.35), maxSwing + 0.35)
        }

        let lenBefore = webLen
        if swinging {
            webLen = approach(webLen, webLenTarget, 1.8, dt)
        } else {
            // Steady paces: it hauls itself up at a climbing speed and pays
            // out silk a little faster, easing off as it gets there.
            let diff = webLenTarget - webLen
            let maxRate = (diff < 0 ? (hurrying ? 140 : 70) : 125) * config.scale
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
        let damping: CGFloat = swinging ? 0.22 : (settling ? 6.0 : 1.6)
        let len = max(webLen + bungee.value, 20)
        let acc = -(g / len) * sin(webAngle) - webAngleVel * damping + limitAcc
        webAngleVel += acc * dt
        webAngle += webAngleVel * dt
        // Bouncing on the line stretches the body with it.
        stretch.value += bungee.velocity * 0.00025

        let dir = V2(sin(webAngle), -cos(webAngle))
        // The line ends at the spinnerets, not the body's middle: the body
        // hangs off that point, so the thread runs exactly along the line
        // through the grips whichever way up it is.
        var attachOff = silkAttachLocal()
        attachOff.x *= mirrorSign
        // Where the body sits relative to that point follows the heading —
        // but eased. Twisting on the line it shows its other side every so
        // often, and at that instant the spinnerets swap sides in sprite
        // space while the heading takes a moment to come round: taken
        // literally, the body would jump the width of its abdomen and wobble
        // back. So the offset slides there instead, and the line, pinned to
        // the real spinnerets, bends a touch until it has.
        let wantOff = -attachOff.rotated(by: heading) * config.scale
        hangOff = approach(hangOff, wantOff, 9, dt)
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

        // Hangs holding the line: body along the thread, hind legs gripping
        // it above the abdomen. Climbing and descending are hand over hand —
        // the feet stay put on the thread while the body moves past them.
        let alongThread = webAngle - .pi / 2                // direction from anchor to spider
        let moved = len - prevHangLen                       // + = descending
        prevHangLen = len
        hangDelta = abs(moved) < 40 ? moved : 0
        if abs(moved) < 40 {
            climbTravel += abs(moved) / (Spider.climbStride * config.scale)
            climbPhase += abs(moved) / (Spider.climbStridePx * config.scale)
            climbDir = approach(climbDir, clamp(-moved / dt / 60, -1, 1), 8, dt)
        }

        if swinging {
            hangHeadUp = false
            updateSwing(dt: dt, alongThread: alongThread, len: len)
            return
        }
        // Climbing, it turns to face up the line and hauls; once it stops it
        // lets itself back round to hang head down.
        // A real climb — a good stretch of line to haul in — it turns to
        // face up the thread for; a small adjustment it makes as it hangs.
        let hauling = webLenTarget < webLen - 3
        stillFor = hauling ? 0 : stillFor + dt
        if hauling, webLen - webLenTarget > 45 * config.scale { hangHeadUp = true } else if stillFor > 0.5 { hangHeadUp = false }
        let headDir = hangHeadUp ? alongThread + .pi : alongThread
        headingTarget = headDir + (facing < 0 ? .pi : 0) + sin(t * 1.3) * 0.03
        wag.step(to: t < twirlUntil ? 0.8 : 0, dt: dt)

        // A window has come over it on the line: straight up and out. Only
        // a window in front of the one it hung from counts — hanging down
        // the face of the very window it dropped off is the point. If the
        // window has come over the top of the line as well, there is
        // nothing up there to climb out onto: it swings off instead.
        if !map.isVisible(pos, depth: webFromDepth) {
            if homeIsOpen {
                webLenTarget = 26
                webPlan = [.climbHome]
                lingerUntil = -1
                twirlUntil = 0
            } else if !leavingLostLine {
                leaveLostLine()
            }
        }

        // Curious about a pointer below it: pays out line to come and see.
        var lingering = false
        if case .linger? = webPlan.first { lingering = true }
        if climbArrival == nil, lingering, config.followCursor, cursorVel.length < 40, cursor.y < webAnchor.y - 60,
           abs(cursor.x - webAnchor.x) < 120 * config.scale, t - lastUserActivity < 6 {
            let want = clamp(webAnchor.y - cursor.y - 48 * config.scale, 30, maxLen)
            webLenTarget = approach(webLenTarget, want, 1.5, dt)
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
            webLenTarget = maxLen
            webStyle = .hang
            swingPumping = false
            decisionIn = 99
        } else if climbArrival == nil {
            decisionIn -= dt * config.liveliness
            // Being reeled about by hand (`decisionIn` pushed out): it does
            // as it is told and picks its plan up again after.
            if decisionIn <= 0 { thinkOnWeb() }
        }

        guard webGrace <= 0, !hangOnly else { return }

        // Climbing up and out (into the habitat): at the top, it is there.
        if let arrive = climbArrival, hangHeadUp || webLenTarget < 30, webLen < 40 {
            climbArrival = nil
            arrive()
            return
        }

        // On its way up and out, nothing on the way distracts it.
        guard climbArrival == nil else { return }

        // Reached the top: climb on. The line may be fastened to the lip
        // of a shelf it fell off, in which case the last bit is a pull-up
        // over the edge.
        if webLen < 34, let spot = map.nearestSpot(to: pos, within: 40 + map.standoff)
            ?? map.nearestSpot(to: webAnchor, within: 40 * config.scale + map.standoff) {
            land(on: spot.anchor, seg: spot.seg)
            return
        }
        // Touched down on something below while barely swinging. Not while
        // it is hauling itself up: on its way somewhere it does not grab at
        // whatever it happens to pass.
        if !hauling, abs(webAngleVel) < 0.7, abs(bungee.velocity) < 40,
           let spot = map.nearestSpot(to: pos, within: 22 * config.scale),
           spot.point.y < pos.y + 6 {
            land(on: spot.anchor, seg: spot.seg)
            return
        }
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
        headingTarget = alongThread + lag + (facing < 0 ? .pi : 0)
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
            prevHangLen = webLen + bungee.value
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
        detachWeb(fade: true)
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
        let forward = seg.dir * walkDir
        let screen = map.screenFrame(containing: pos)
        // From the floor there is nothing to swing down from, so the line has
        // to go out well ahead and it reels in hard; from up high, a steeper
        // line gives a proper drop.
        let onFloor = pos.y - screen.minY < 80
        var best: (score: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) where spot.loop.id != anchor.loopID || spot.loop.kind == .screenBorder {
            let a = spot.point - spot.seg.normal * map.standoff        // the edge itself
            let d = a - pos
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
        guard let target = best else { return false }
        shotTarget = target.point
        shotPurpose = .swing
        shotProgress = 0
        queued = nil
        beginActivity(.shoot, dur: 0.28)
        return true
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
            let len = clamp(max(webLen, 170 * config.scale), 110, min(maxLen, 420))
            webPlan = [.swingOff(len)]
        } else {
            webPlan = [.toFloor]
        }
        lingerUntil = -1
        twirlUntil = 0
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
            webLenTarget = l
            if abs(webLen - l) < 4 { webPlan.removeFirst(); lingerUntil = -1 }
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
            webLenTarget = 26
            // Reached the top: the landing check below takes it from here —
            // unless there is nothing there to take hold of any more (the
            // window has gone, or something has come over it): then down
            // it goes instead, rather than hanging under nothing.
            if webLen < 34, !homeIsOpen { leaveLostLine() }
        case .toFloor:
            let screen = map.screenFrame(containing: webAnchor)
            let floorLen = max(40, webAnchor.y - (screen.minY + 30 * config.scale))
            webLenTarget = floorLen
            // Down as far as the line goes and nothing to step onto: back up.
            if webLen > floorLen - 3, abs(webAngleVel) < 0.3 {
                if floorWait < 0 { floorWait = t }
                if t - floorWait > 2.5 { webPlan = [.climbHome] }
            } else {
                floorWait = -1
            }
        case .swing:
            webPlan.removeFirst()
            if webLen > 90, !confined { workUpSwing() } else { webPlan = [.climbHome] }
        case .swingOff(let l):
            webLenTarget = l
            if abs(webLen - l) < 4 {
                webPlan.removeFirst()
                if webLen > 90, !confined { workUpSwing() } else { webPlan = [.toFloor] }
            }
        case .jumpOff:
            webPlan.removeFirst()
            if let spot = bestJumpSpot(from: pos, exclude: ""), let launch = ballistic(from: pos, to: spot.point) {
                detachWeb(fade: true)
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
        webAnchor = p
        webActive = true
        webFromDepth = map.occluders.filter { $0.rect.insetBy(dx: -4, dy: -4).contains(p.point) }.map(\.depth).min() ?? Int.max
        webPlan = []
        lingerUntil = -1
        let r = pos - p
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
        climbTravel = 0
        hangHeadUp = false
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
        if overstretched || !map.isOnScreen(webAnchor, slack: 60) {
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
        if webActive && fade {
            // A slow fade, so the let-go line can be seen drifting down.
            webAlpha = Spring(0.7, stiffness: 14, damping: 7.6)
        }
        webActive = false
    }

    private func dropOnWeb() {
        guard config.webs else { return }
        // Anchor the thread on the edge it is gripping, not in mid-air.
        var a = pos
        webFromDepth = Int.max
        if let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count {
            a = pos - loop.segs[anchor.segIdx].normal * map.standoff
            webFromDepth = loop.depth
        }
        webAnchor = a
        webActive = true
        webLen = 22
        webLenTarget = randRange(150, 430)
        webAngle = 0
        webAngleVel = randRange(-0.15, 0.15)
        webStyle = .hang
        bungee.reset(0)
        prevHangLen = webLen
        climbTravel = 0
        hangHeadUp = false
        stillFor = 0
        mode = .dangling
        hangOffFresh = true
        hangTwistPhase = -t * 0.45
        legMode = .free
        queued = nil
        decisionIn = randRange(0.3, 0.8)
        webGrace = 0.9
        let screen = map.screenFrame(containing: a)
        planWeb(maxLen: max(40, a.y - (screen.minY + 30 * config.scale)))
        if case .descend(let l)? = webPlan.first { webLenTarget = l }
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
            case .sleep: enterNest()
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
            hammock = nil
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
                hammock = h
                happy.velocity = 6
                setEmote(.sparkle, 1.0)
                if wantsSleepAfterBuild {
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
        } else if mode == .clinging || cursorHunt != .none || interest > 0.05 {
            // Eyes locked on the pointer.
            target = (cursor - pos).normalized
        } else if watching {
            target = (cursor - pos).normalized
        } else if speed > 2 {
            target = V2.angle(heading) * facing * 0.6
        } else if activity == .peek {
            target = (V2.angle(heading) * facing + V2(0, -1)).normalized * 0.8
        } else {
            idleLookIn -= dt
            if idleLookIn <= 0 {
                idleLookIn = randRange(0.6, 2.6)
                idleLook = chance(0.3) ? .zero : V2.angle(randRange(-.pi, .pi)) * randRange(0.3, 0.8)
            }
            target = idleLook
        }
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

    /// A foot on the line: `at` units along `dir` from `origin`, offset a
    /// touch to `side` so the pad sits on the line's flank — pulled back
    /// along the line to the nearest point this leg can actually reach, so
    /// a short leg holds the line close to the body rather than straining
    /// past it.
    private func grip(on origin: V2, dir: V2, at: CGFloat, side: V2, leg i: Int) -> V2 {
        let profile = SpiderRenderer.profileAmount(yaw: yaw)
        let r = SpiderRenderer.rig(i, profile: profile, look: look)
        let reach = ((r.knee - r.hip).length + (r.foot - r.knee).length) * 0.97
        let pad: CGFloat = 1.6
        // Points on the line, as seen from the hip: p + dir * s.
        let p = origin + side * pad - r.hip
        let mid = -p.dot(dir)
        let disc = reach * reach - (p.lengthSquared - mid * mid)
        var s = at
        if disc <= 0 {
            s = mid                                   // out of reach: the nearest point
        } else {
            let half = disc.squareRoot()
            s = clamp(at, mid - half, mid + half)
        }
        return origin + side * pad + dir * s
    }

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
        case (.dangling, _):
            if t < twirlUntil {
                // Tucked in for the twirl.
                return leg.hip + reach * 0.5 + V2(2, 2)
            }
            // The thread leaves the spinnerets and the body hangs in line
            // with it, so "on the line" is a point along that direction from
            // the spinnerets. Near-side legs hook it from underneath and
            // far-side legs from over the top, knees bent outward, so the
            // line runs between them. Head down, the hind pairs hold the
            // line above the abdomen and the front pairs fold; head up, the
            // front pairs haul on the line above the head and the hind pairs
            // work the loose silk trailing below. Each gripping leg takes a
            // stroke of line: through its stance the foot holds still in the
            // world, sliding through the sprite frame as the body moves
            // past; then it opens, reaches on and closes again.
            let spin = silkAttachLocal()
            let lineDir = (toLocal(webAnchor) - spin).normalized
            let ventral = V2(0, -1)
            let side = near ? ventral : -ventral
            var hold: (lo: CGFloat, hi: CGFloat, phase: CGFloat)?
            if hangHeadUp {
                switch k {
                case 0: hold = (54, 68, near ? 0 : 0.5)
                case 1: hold = (38, 50, near ? 0.25 : 0.75)
                case 2: hold = (5, 15, near ? 0.55 : 0.05)
                case 3: hold = (-15, -3, near ? 0.8 : 0.3)
                default: hold = nil
                }
            } else {
                switch k {
                case 3: hold = (1, 11, near ? 0 : 0.5)
                case 2: hold = (-2, 2, near ? 0.25 : 0.75)
                default: hold = nil
                }
            }
            guard let h = hold else {
                let drift = V2(leg.wobble.value(t * 0.9) * 2, leg.wobble.value(t * 0.7 + 3) * 2)
                if webStyle == .swing {
                    // Swinging, the front legs hang loose toward the ground,
                    // trailing the motion — and kick with it while it is
                    // pumping the swing up.
                    let down = toLocalDir(V2(0, -1))
                    let kick = toLocalDir(swingVel).clampedLength(1) * (swingPumping ? 9 : 3)
                    return leg.hip + down * (16 + (k == 0 ? 3 : 0) + (near ? 0 : 2)) + kick + drift
                }
                // Head down: the front legs fold in toward the face, half
                // curled, and stir now and then.
                let curl: CGFloat = k == 0 ? 15 : 9
                return V2(leg.hip.x + curl, -10 - CGFloat(k) * 2 + (near ? 0 : 1.5)) + drift
            }
            legBend[i] = side
            let stance: CGFloat = 0.7
            // Moving head first along the line (climbing head up, or
            // descending head down) a held foot slides from hi to lo through
            // the sprite frame; tail first, the other way. Between moves it
            // just holds on.
            let headFirst = hangHeadUp ? climbDir >= 0 : climbDir <= 0
            var u = (climbTravel + h.phase).truncatingRemainder(dividingBy: 1)
            if u < 0 { u += 1 }
            let start = headFirst ? h.hi : h.lo
            let finish = headFirst ? h.lo : h.hi
            var along: CGFloat
            var open: CGFloat = 0
            if u < stance {
                along = lerp(start, finish, u / stance)
            } else {
                let w = smoothstep((u - stance) / (1 - stance))
                along = lerp(finish, start, w)
                open = sin(w * .pi) * 5 * min(abs(climbDir) * 3, 1)   // opens off the line to reach
            }
            if abs(climbDir) < 0.05 { along += leg.wobble.value(t * 0.6) * 0.8 }
            return grip(on: spin, dir: lineDir, at: along, side: side, leg: i) + side * open
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
            return leg.hip + reach * 0.72 + V2(0, leg.wobble.value(t * 0.5) * 0.6)
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
            // Tucked up under it for the instant it is in the air.
            let h = sin(clamp(u, 0, 1) * .pi)
            return V2.lerp(rest, leg.hip + reach * 0.55 + V2(0, 3), h)
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
        case (.attached, .bounce):
            // Off the ground mid-hop: legs tuck slightly.
            return leg.hip + reach * 0.85 + V2(0, 4)
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
        if absorbingLanding { leg.settleTo = target }
        leg.settle += dt / (quick ? landStep : 0.24)
        let u = clamp(leg.settle, 0, 1)
        leg.lift = sin(u * .pi) * (quick ? 0.3 : 0.7)
        leg.foot = stepPath(i, from: leg.swingFrom, to: leg.settleTo, u: u) + V2(0, leg.lift * 3.5)
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
    private var modeBeforeLegs: Mode = .attached
    private static let handoffTime: CGFloat = 0.26
    /// Tools only: the hand-offs and the jolt limits, off, to compare.
    static var debugRawLegs = false

    private func updateLegs(dt: CGFloat) {
        let before = legs.map(\.foot)
        let was = legController
        updateLegControllers(dt: dt)
        defer { limitFootJolts(dt: dt) }
        let onSurface = mode == .attached || mode == .nesting
        if legController != was {
            // A step in flight belongs to the clock that started it; the
            // next controller begins its own.
            for i in legs.indices { legs[i].swinging = false }
            // Eased only from one way of standing to another, or onto a
            // line. Picked up, launched, falling, the feet go with the body
            // at once; landing, the landing has them (see `absorbingLanding`).
            let eased = (onSurface && modeBeforeLegs == mode && !absorbingLanding) || mode == .dangling
            if eased, !Spider.debugRawLegs {
                handoffFrom = before
                handoffT = 0
            } else {
                handoffT = 1
            }
        }
        modeBeforeLegs = mode
        if mode == .held || mode == .airborne || absorbingLanding { handoffT = 1 }
        guard handoffT < 1, handoffFrom.count == legs.count else { return }
        handoffT = min(1, handoffT + dt / Spider.handoffTime)
        let e = smoothstep(handoffT)
        for i in legs.indices {
            // On a surface the start point stays on the ground while the
            // body moves; on a line it goes with the body.
            if onSurface { handoffFrom[i] = handoffFrom[i].rotated(by: -legDTheta) - legOverFeet }
            legs[i].foot = V2.lerp(handoffFrom[i], legs[i].foot, e)
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
        let onSurface = (mode == .attached || mode == .nesting) && activity != .roll
        let bodyJump = pos.distance(to: footLimitPos) > 30 * config.scale
        footLimitPos = pos
        guard onSurface, !bodyJump, !Spider.debugRawLegs, dt > 0, footWorld.count == legs.count, footWorldVel.count == legs.count else {
            footWorldVel = footWorld.count == world.count ? zip(world, footWorld).map { ($0 - $1) / max(dt, 0.001) }
                : Array(repeating: .zero, count: world.count)
            footWorld = world
            return
        }
        let cap = Spider.footJolt * config.scale * (absorbingLanding ? 3 : 1)
        for i in legs.indices {
            var w = world[i]
            if Spider.limitJolt(&w, last: &footWorld[i], vel: &footWorldVel[i], cap: cap, dt: dt) {
                legs[i].foot = toLocal(w)
            }
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
                let target = groundFoot(SpiderRenderer.rig(i, profile: profile, look: look).foot, spread: true)
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

        // On a line, the legs climb it hand over hand.
        if mode == .dangling, webStyle == .hang, t >= twirlUntil {
            legController = .hang
            updateHangLegs(dt: dt)
            return
        }

        // Feet are free while the body is well round toward the front view;
        // a mere glance keeps them stepping.
        // (A little either way of the switch-over, so a body hovering about
        // it — following the pointer — does not flap between the two.)
        guard legMode == .planted, facing == m, profile > (legController == .posed ? 0.55 : 0.45) else {
            legController = .posed
            // On a ledge, a gesture is eased into from wherever the feet
            // were, and eased out of back to standing before it ends.
            let eased = mode == .attached && Spider.easedPoses.contains(activity)
            let rise = eased ? smoothstep(clamp((t - activityStarted) / Spider.poseEaseIn, 0, 1)) : 1
            let fall = eased && activityDur > Spider.poseEaseOut * 2 && activity != .sleep
                ? smoothstep(clamp((activityDur - activityTime) / Spider.poseEaseOut, 0, 1)) : 1
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
        legController = .gait
        let stride = strideNow
        let landAhead = stride * (1 - duty) * 0.5
        let walking = speed > 1

        for i in legs.indices {
            var leg = legs[i]
            leg.footVel = .zero
            let ph = (gaitPhase + leg.phase).truncatingRemainder(dividingBy: 1)

            if ph >= duty { leg.skipSwing = false }
            if walking, ph < duty, !leg.swinging, ph > duty * 0.3 { leg.skipSwing = true }
            if walking && ph < duty && !leg.skipSwing {
                leg.settle = -1
                if !leg.swinging {
                    leg.swinging = true
                    leg.swingFrom = leg.foot
                    leg.swingPh0 = ph
                } else {
                    // The step runs over the ground, not with the body: it
                    // leaves from the spot the foot stood on, which stays
                    // where it is while the body carries on over it.
                    leg.swingFrom = leg.swingFrom.rotated(by: -dTheta) - deltaLocal
                }
                let u = clamp((ph - leg.swingPh0) / max(duty - leg.swingPh0, 0.01), 0, 1)
                // Land on the edge itself, wherever that is relative to the
                // body — at the spot on the ground that will be there at
                // touchdown, not where it is now. Both ends of the step are
                // then still on the ground, so the foot lifts off and sets
                // down at rest instead of being yanked from a standstill to
                // the body's pace and stopped dead again.
                let restNow = SpiderRenderer.rig(i, profile: profile, look: look).foot
                let ahead = (duty - ph) * stride   // body travel before it lands
                let target = groundFoot(restNow + travelLocal * (landAhead + ahead), spread: true)
                let base = stepPath(i, from: leg.swingFrom, to: target, u: u)
                // Eased off and onto the ledge at both ends of the arc.
                leg.lift = pow(sin(u * .pi), 1.5)
                // The foot lifts clear of the ledge on a shallow arc — higher
                // when it is being bouncy or walking on tiptoe.
                let stepHeight: CGFloat = gaitStyle == .bouncy ? 8 : (gaitStyle == .tiptoe ? 6.5 : 5)
                leg.foot = base + V2(0, leg.lift * stepHeight)
            } else {
                leg.swinging = false
                leg.lift = approach(leg.lift, 0, 16, dt)
                if walking {
                    // Stance: hold station on the ledge while the body moves
                    // — unless the foot is still in the air from before, in
                    // which case it steps down first.
                    let rest = groundFoot(SpiderRenderer.rig(i, profile: profile, look: look).foot, spread: true)
                    if leg.settle >= 0 || leg.foot.y > max(rest.y, leg.hip.y) + 5 {
                        _ = settleFoot(&leg, i, to: rest, dt: dt)
                        legs[i] = leg
                        continue
                    }
                    leg.foot = leg.foot.rotated(by: -dTheta) - deltaLocal
                    let g = groundFoot(leg.foot)
                    leg.foot = leg.foot.distance(to: g) > 2 ? approach(leg.foot, g, 14, maxSpeed: 240, dt) : g
                    // Never let a foot be dragged past what the leg can reach.
                    let reach = leg.foot - leg.hip
                    let maxReach = (leg.rest - leg.hip).length * 1.4
                    if reach.length > maxReach {
                        leg.foot = groundFoot(leg.hip + reach.normalized * maxReach)
                    }
                } else {
                    // Standing: settle onto the rest pose — on the edge, which
                    // round a corner is not where the rest pose says — with a
                    // little idle shuffle so it never looks frozen. A foot
                    // left well off its spot (mid-stride when it stopped, or
                    // up in the air from a wave) takes one small step there;
                    // the legs go one at a time, in gait order.
                    var rest = SpiderRenderer.rig(i, profile: profile, look: look).foot
                    rest.x += leg.wobble.value(t * 0.8) * 0.5
                    let target = groundFoot(rest, spread: true)
                    // A planted foot holds its place in the world while the
                    // body moves over it — coming down and lurching out of
                    // a landing, leaning, breathing — the leg giving, never
                    // dragged into the ledge with it; then eases to its spot.
                    if leg.settle < 0 {
                        leg.foot = leg.foot.rotated(by: -dTheta) - overFeet
                        let reach = leg.foot - leg.hip
                        let maxReach = (leg.rest - leg.hip).length * 1.4
                        if reach.length > maxReach { leg.foot = groundFoot(leg.hip + reach.normalized * maxReach) }
                    }
                    // One leg at a time unless a foot is well out of place.
                    let othersBusy = !absorbingLanding && legs.contains(where: { $0.settle >= 0 }) && leg.settle < 0
                    if othersBusy && leg.foot.distance(to: target) <= 14 || !settleFoot(&leg, i, to: target, dt: dt) {
                        leg.foot = approach(leg.foot, target, absorbingLanding ? 30 : 9, dt)
                    }
                }
            }
            legs[i] = leg
        }
    }

    // MARK: - Climbing a line

    /// The legs on the line work like the walking legs on a ledge, only the
    /// "ledge" is the thread running along the body's own axis. Each
    /// gripping leg has a natural spot on the line; in its stance the foot
    /// holds still in the world (so it slides through the sprite frame as
    /// the body climbs or descends past it), and in its swing it lets go,
    /// lifts off the line to its own side — over the legs still holding —
    /// and reaches on to its next grip, a stride ahead. Near-side legs hook
    /// the line from one side, far-side legs from the other. Head down,
    /// only the hind two pairs hold (the front pairs fold in); head up,
    /// climbing, every pair hauls.
    private func updateHangLegs(dt: CGFloat) {
        let sc = max(config.scale, 0.05)
        for i in legs.indices { legs[i].settle = -1 }
        let spin = silkAttachLocal()
        let lineDir = (toLocal(webAnchor) - spin).normalized
        let ventral = V2(0, -1)
        let moving = abs(climbDir) > 0.05 && abs(hangDelta) > 0.0001
        // Through a stance the foot drifts: toward the anchor when the body
        // is descending past it, away from it when climbing.
        let stanceDir = hangDelta >= 0 ? lineDir : -lineDir
        let drift = abs(hangDelta) / sc                    // sprite units this frame
        let duty: CGFloat = 0.32
        let stride = Spider.climbStridePx                  // sprite units (px at scale 1)
        let landAhead = stride * (1 - duty) * 0.5

        for i in legs.indices {
            var leg = legs[i]
            let near = i < 4
            let k = i % 4
            let side = near ? ventral : -ventral
            // Its natural grip along the line, and its place in the cycle.
            var rest: CGFloat?
            var phase: CGFloat = 0
            if hangHeadUp {
                switch k {
                case 0: rest = 56; phase = near ? 0 : 0.5
                case 1: rest = 42; phase = near ? 0.25 : 0.75
                case 2: rest = 8; phase = near ? 0.5 : 0
                default: rest = -10; phase = near ? 0.75 : 0.25
                }
            } else {
                switch k {
                case 3: rest = 6; phase = near ? 0 : 0.5
                case 2: rest = -1; phase = near ? 0.5 : 0
                default: rest = nil
                }
            }
            guard let r = rest else {
                // Folded in toward the face, stirring now and then.
                let wob = V2(leg.wobble.value(t * 0.9) * 2, leg.wobble.value(t * 0.7 + 3) * 2)
                let curl: CGFloat = k == 0 ? 15 : 9
                let target = V2(leg.hip.x + curl, -10 - CGFloat(k) * 2 + (near ? 0 : 1.5)) + wob
                leg.foot = approach(leg.foot, target, 7, maxSpeed: 220, dt)
                leg.lift = approach(leg.lift, 0, 8, dt)
                leg.swinging = false
                legBend[i] = nil
                legs[i] = leg
                continue
            }
            legBend[i] = side
            let ph = (climbPhase + phase).truncatingRemainder(dividingBy: 1)
            if moving, ph < duty {
                // Let go and reach on: an arc off the line to its own side
                // — paced from wherever in its window the reach began.
                if !leg.swinging {
                    leg.swinging = true
                    leg.swingFrom = leg.foot
                    leg.swingPh0 = min(ph, duty * 0.6)
                }
                let u = clamp((ph - leg.swingPh0) / max(duty - leg.swingPh0, 0.01), 0, 1)
                let target = grip(on: spin, dir: lineDir, at: r - (stanceDir.dot(lineDir)) * landAhead, side: side, leg: i)
                let base = V2.lerp(leg.swingFrom, target, easeInOutSine(u))
                leg.lift = sin(u * .pi)
                leg.foot = base + side * (leg.lift * 5.5)
            } else if moving {
                // Holding on: the foot stays put in the world as the body
                // moves past it — never past what the leg can reach.
                leg.swinging = false
                leg.lift = approach(leg.lift, 0, 14, dt)
                let along = (leg.foot - spin).dot(lineDir) + stanceDir.dot(lineDir) * drift
                let limited = clamp(along, r - stride * 0.8, r + stride * 0.8)
                let hold = grip(on: spin, dir: lineDir, at: limited, side: side, leg: i)
                // A foot not yet on the line (it has only just taken to it)
                // reaches for its grip rather than appearing there.
                leg.foot = leg.foot.distance(to: hold) > 6 ? approach(leg.foot, hold, 10, maxSpeed: 260, dt) : hold
            } else {
                // Hanging still: settles onto its grip, with the odd shift.
                leg.swinging = false
                leg.lift = approach(leg.lift, 0, 8, dt)
                let target = grip(on: spin, dir: lineDir, at: r + leg.wobble.value(t * 0.6) * 1.2, side: side, leg: i)
                leg.foot = approach(leg.foot, target, 7, maxSpeed: 220, dt)
            }
            leg.footVel = .zero
            legs[i] = leg
        }
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
        case "hearts": setEmote(.hearts, 1.2)
        case "zzz": setEmote(.zzz, 3)
        default: break
        }
    }

    /// Tools only: the pendulum's state.
    var debugSwing: (angle: CGFloat, angVel: CGFloat) { (webAngle, webAngleVel) }

    /// Tools only: the line's length and where it is heading.
    var debugLine: (len: CGFloat, target: CGFloat, style: String, pumping: Bool) {
        (webLen, webLenTarget, webStyle == .swing ? "swing" : "hang", swingPumping)
    }

    /// Tools only: is the pointer where a hanging spider would go to look at it?
    var debugCursorNear: Bool {
        config.followCursor && cursor.y < webAnchor.y - 60 && abs(cursor.x - webAnchor.x) < 120 * config.scale && t - lastUserActivity < 6
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

    func debugActivity(_ name: String, for seconds: CGFloat) {
        let table: [String: Activity] = [
            "walk": .walk, "sneak": .sneak, "scurry": .scurry, "look": .look, "rest": .rest,
            "groom": .groom, "sleep": .sleep, "wave": .wave, "startle": .startle,
            "peek": .peek, "stretch": .stretch, "shake": .shake, "wiggle": .wiggle,
            "bounce": .bounce, "curious": .curious, "fidget": .fidget, "scratch": .scratch,
            "armsUp": .armsUp, "roll": .roll, "dance": .dance, "glance": .glance, "peer": .peer,
            "pushup": .pushup, "legStretch": .legStretch, "spin": .spin, "eat": .eat, "watch": .watch,
            "peekaboo": .peekaboo, "greet": .greet, "drum": .drum, "stare": .stare, "hop": .hop,
            "fasten": .fasten,
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

    private func bodySquash() -> (stretch: CGFloat, fatten: CGFloat) {
        // Only a touch of squash for a crouch — the lowering is the body
        // coming down on its legs (see `crouchDrop`).
        let squash = 1 - clamp(crouch.value, 0, 1) * 0.07
        return (clamp(stretch.value * (1 + (1 - squash) * 0.5), 0.74, 1.22),
                clamp(fatten.value * squash, 0.66, 1.26))
    }

    private var bodyPitchNow: CGFloat { clamp(pitch.value + runNose, -0.6, 0.6) }

    /// Leg `i` as drawn: hip and foot where the pose puts them, and the
    /// knee the leg models ask for. The lean turns the hips (and a foot in
    /// the air) about the pivot; the squash and stretch scales the whole
    /// sprite about its ground line, and the feet are taken out of it, so a
    /// splat or a crouch does not shove a planted foot along the ledge (or,
    /// tilted, into it).
    private func modelLeg(_ i: Int, profile: CGFloat) -> (hip: V2, foot: V2, knee: V2) {
        let bp = bodyPitchNow
        let shift = V2(-bp * 8, bp * 2)
        let pivot = SpiderRenderer.leanPivot
        func leaned(_ v: V2) -> V2 { pivot + (v - pivot).rotated(by: bp) + shift }
        let onSurface = mode == .attached || mode == .nesting
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
        let drawnFoot = onSurface ? foot : V2(foot.x * sq.stretch, g + (foot.y - g) * sq.fatten)
        let drawnKnee: V2
        if let bend = legBend[i] {
            let own = SpiderRenderer.kneeIK(leg: i, hip: drawnHip, foot: drawnFoot, away: bend, profile: profile, look: look)
            if let other = legBones[i] {
                // Borrowed proportions come in as the foot rises off the
                // ledge, not all at once at the start of the gesture.
                let w = smoothstep(clamp((leg.foot.y - leg.rest.y) / 22, 0, 1))
                let borrowed = SpiderRenderer.kneeIK(leg: other, hip: drawnHip, foot: drawnFoot, away: bend, profile: profile, look: look)
                drawnKnee = V2.lerp(own, borrowed, w)
            } else {
                drawnKnee = own
            }
        } else {
            drawnKnee = SpiderRenderer.knee(leg: i, hip: drawnHip, foot: drawnFoot, lift: leg.lift, profile: profile, look: look)
        }
        if onSurface { foot = V2(foot.x / sq.stretch, g + (foot.y - g) / sq.fatten) }
        let knee = V2(drawnKnee.x / sq.stretch, g + (drawnKnee.y - g) / sq.fatten)
        return (hip, foot, knee)
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
        let k = 1 - exp(-dt * 24)
        // On a surface the knees come under the same limit as the feet: a
        // knee riding a hip-to-foot line that swings round fast (a foot
        // passing close under the hip) is held to a movement too.
        let limit = (mode == .attached || mode == .nesting) && activity != .roll && !fresh && !Spider.debugRawLegs
            && kneeWorld.count == legs.count && kneeWorldVel.count == legs.count && dt > 0
            && pos.distance(to: kneeLimitPos) < 30 * config.scale
        kneeLimitPos = pos
        if kneeWorld.count != legs.count { kneeWorld = Array(repeating: .zero, count: legs.count) }
        if kneeWorldVel.count != legs.count { kneeWorldVel = Array(repeating: .zero, count: legs.count) }
        kneeLocal = legs.indices.map { i in
            let j = modelLeg(i, profile: profile)
            let want = Spider.kneeShape(hip: j.hip, foot: j.foot, knee: j.knee)
            kneeShape[i] = fresh ? want : kneeShape[i] + (want - kneeShape[i]) * k
            let local = Spider.knee(from: kneeShape[i], hip: j.hip, foot: j.foot)
            var w = kneeWorldPoint(local)
            if limit {
                if Spider.limitJolt(&w, last: &kneeWorld[i], vel: &kneeWorldVel[i], cap: Spider.footJolt * config.scale * (absorbingLanding ? 3 : 1), dt: dt) {
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
        p.blink = clamp(max(blinkValue, sleepiness.value, lid.value), 0, 1)
        p.happy = clamp(happy.value + pettingScore * 0.5 + fed * 0.3, 0, 1)
        if activity == .eat, mode == .attached { p.chew = 0.5 + 0.5 * sin(t * 11) }
        // A nibble at the pointer it has caught, now and then.
        if mode == .clinging { p.chew = max(0, sin(t * 7)) * (0.5 + 0.5 * sin(t * 0.9)) }
        p.headTilt = headTilt.value
        // It is drawn in front of everything, and it stays there: it never
        // slips behind a window. The one exception is peek-a-boo, where
        // hiding behind the edge of a window in front of the one it stands
        // on is the whole game — then the parts of it inside that window
        // are behind it.
        if mode == .attached, activity == .peekaboo, let loop = map.loop(anchor.loopID), loop.kind == .windowEdge {
            let r = 62 * config.scale
            let sprite = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            p.hiddenBy = map.occluders.filter { $0.depth < loop.depth && $0.rect.intersects(sprite) }.map { $0.rect }
        }
        p.startled = clamp(startled.value, 0, 1)
        p.sleep = clamp(sleepiness.value, 0, 1)
        p.abdomenSway = swayWobble.value(t * 1.4) * 0.14
            + sin(gaitPhase * .pi * 2) * 0.09 * min(speed / 60, 1)
            + sin(wagPhase) * wag.value * 0.55
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
        if mode == .dangling, webActive, let web = p.web {
            // The held stretch of line, in sprite units, plus the loose silk
            // trailing behind the spinnerets while it hauls itself up.
            let a = silkAttachLocal()
            let dir = (toLocal(webAnchor) - a).normalized
            let tail: CGFloat = webStyle == .hang && hangHeadUp ? 1 : 0
            p.thread = (a, a + dir * 80, tail, web.alpha)
        }
        return p
    }
}
