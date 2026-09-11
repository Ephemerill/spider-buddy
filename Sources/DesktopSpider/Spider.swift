import AppKit
import CoreGraphics

// MARK: - Configuration

struct SpiderConfig {
    var scale: CGFloat = 1.0
    var walkSpeed: CGFloat = 62          // px/s at scale 1
    var liveliness: CGFloat = 1.0        // how often it decides to do something
    var followCursor: Bool = true
    var webs: Bool = true
    var paused: Bool = false
}

// MARK: - Pose handed to the renderer (all body-local unless noted)

enum Emote {
    case none, hearts, zzz, surprise, sparkle, question, note
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
    var emoteT: CGFloat = 0
    var web: (anchor: V2, alpha: CGFloat, slack: CGFloat)?
    /// The line as a chain of world points, anchor first, when it is live.
    var webPoints: [V2] = []
    /// The stretch of line it is holding, in sprite units, drawn between the
    /// far legs and the body so the legs read as gripping it from both sides.
    /// `tail` is how much loose silk trails out behind the spinnerets.
    var thread: (a: V2, b: V2, tail: CGFloat, alpha: CGFloat)?
    var time: CGFloat = 0
    var dragline: (from: V2, alpha: CGFloat)?
    var grabbed: CGFloat = 0
    /// How it is dressed.
    var outfit = SpiderLook()
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
    var lift: CGFloat = 0

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
}

/// What it is doing on the end of a thread.
private enum WebStyle { case hang, swing }
private enum NestPhase { case building, sleeping }
private enum HomeGoal { case build, sleep, corner }

/// The silk retreat a jumping spider spins in a sheltered corner: a sling
/// strung across the corner from the wall to the underside of the menu bar,
/// sagging like a hammock, with the corner itself left open behind it.
struct Hammock: Equatable {
    var left: Bool            // which top corner of the screen
    var rect: CGRect          // world; the sling and its anchors fit inside
    var progress: CGFloat     // 0..1 as it is spun
    var damage: CGFloat       // 0..1 as you wipe it away

    /// Out along the ceiling, and down the wall.
    var ceilingAnchor: V2 { V2(left ? rect.maxX - 4 : rect.minX + 4, rect.maxY - 2) }
    var wallAnchor: V2 { V2(left ? rect.minX + 2 : rect.maxX - 2, rect.maxY - rect.height * 0.62) }
    /// How far the middle hangs below the straight line between the anchors.
    var sag: CGFloat { rect.height * 0.5 }

    /// The sling's centre line, a quadratic from the wall to the ceiling;
    /// `drop` lowers the control point (torn, or weighed down).
    func point(at u: CGFloat, drop: CGFloat = 0) -> V2 {
        let a = wallAnchor, b = ceilingAnchor
        let c = (a + b) * 0.5 + V2(0, -(sag + drop) * 2)
        let v = 1 - u
        return a * (v * v) + c * (2 * v * u) + b * (u * u)
    }
    func tangent(at u: CGFloat) -> V2 {
        let a = wallAnchor, b = ceilingAnchor
        let c = (a + b) * 0.5 + V2(0, -sag * 2)
        return ((c - a) * (1 - u) + (b - c) * u).normalized
    }
    /// The bottom of the sag, where it lies.
    var bed: V2 { point(at: 0.5) }
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
}

/// How it carries itself on a given walk.
private enum GaitStyle { case normal, bouncy, tiptoe, lumber }

private enum AirKind { case jump, fall, thrown }
private enum TurnStyle { case hop, shuffle }

// MARK: - Spider

final class Spider {
    var config = SpiderConfig()
    let map: SurfaceMap
    /// The studio's design: how it looks, who it is, how it walks.
    var look = SpiderLook()
    var personality = Personality() {
        didSet { config.liveliness = personality.liveliness }
    }
    var gait = Gait()
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
    private var lift = Spring(0, stiffness: 140, damping: 17)      // height off the ledge
    private var pitch = Spring(0, stiffness: 120, damping: 16)     // nose up (+) / down (-)
    /// A touch of nose-down when running, folded into the body lean.
    private var runNose: CGFloat = 0
    /// Where a leap is going to land, if it knows: it turns and reaches for
    /// the surface over the last stretch of flight instead of snapping on.
    private var landing: (point: V2, angle: CGFloat, dir: V2)?
    private var landingReach: CGFloat = 0
    /// The roll: distance travelled while balled up, which is what turns it.
    private var rollTravel: CGFloat = 0
    private var rollSpinEnd: CGFloat = 0
    private var rollLanded = false
    private var crouch = Spring(0, stiffness: 200, damping: 20)
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
    private var decisionIn: CGFloat = 1.2
    private var airTime: CGFloat = 0
    private var noAttachFor: CGFloat = 0
    private var launchLoop: String = ""
    private var blinkIn: CGFloat = 2
    private var blinkT: CGFloat = -1
    private var blinkTwice = false
    private var occludedFor: CGFloat = 0
    /// An escape from under a window is under way until then: the covered
    /// check must not keep restarting it, which is what used to freeze it
    /// mid-crouch.
    private var escapeUntil: CGFloat = 0
    /// What a fired line is for: a swing, or a straight climb out of the way.
    private enum ShotPurpose { case swing, climb }
    private var shotPurpose: ShotPurpose = .swing
    /// Climbing out from under a window: hauls at double pace.
    private var hurrying = false

    // Food
    /// Everything loose on the desktop to hunt, plus whatever it is eating.
    private(set) var prey: [Prey] = []
    private var nextPreyID = 1
    private var huntTarget: Int?
    private var huntSince: CGFloat = 0
    private var huntPauseUntil: CGFloat = 0
    /// The current leap is a pounce at the prey.
    private var huntPounce = false
    private var lastPounceAt: CGFloat = -10
    private var caught: Prey?
    /// How well fed it is, 0..1: a good meal keeps it cheerful for a while.
    private(set) var fed: CGFloat = 0
    private var lastUserActivity: CGFloat = 0
    private var lastCurious: CGFloat = -10
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
    private var anchorValid = false
    private var surfaceNormal = V2(0, 1)
    private var legFramePos = V2.zero
    private var legFrameHeading: CGFloat = 0
    private var emote: Emote = .none
    private var emoteTime: CGFloat = 0
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
    private var swingReleaseAfter = 1
    private var lastSwingVelSign: CGFloat = 0
    private var swingFromLoop = ""
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
    private var dragFrom: V2 = .zero
    private var dragAlpha: CGFloat = 0

    // Jump bookkeeping
    private var pendingJump: V2?

    /// Some app has the whole display. Out of the way: asleep in the
    /// hammock if there is one, else tucked into a bottom corner.
    var fullScreenApp = false {
        didSet {
            guard fullScreenApp != oldValue else { return }
            if fullScreenApp {
                if mode == .attached { queued = nil; decisionIn = min(decisionIn, 0.5) }
            } else {
                if homing == .corner { homing = nil }
                if activity == .sleep && mode == .attached { wake() }
                decisionIn = min(decisionIn, 1.0)
            }
        }
    }

    // Hammock
    private(set) var hammock: Hammock?
    private var homing: HomeGoal?
    private var homingSince: CGFloat = 0
    private var nestPhase: NestPhase = .building
    private var nestTime: CGFloat = 0
    private var nestDur: CGFloat = 8
    private var nestAngle: CGFloat = 0
    private var nestZzzIn: CGFloat = 1
    private var wantsSleepAfterBuild = false

    // Cursor
    private var cursor = V2.zero
    private var cursorVel = V2.zero
    private var prevCursor = V2.zero
    private var pettingScore: CGFloat = 0
    private var lastPetSign: CGFloat = 0

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

    var grabRadius: CGFloat { 30 * config.scale }

    func hitTest(_ p: V2) -> Bool {
        p.distance(to: pos) < grabRadius
    }

    func beginGrab(at p: V2) {
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
            beginDragline(from: pos)
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
    func celebrate() {
        wake()
        happy.velocity = 10
        setEmote(.hearts, 1.3)
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
        SpiderDesign(name: name, look: look, personality: personality, gait: gait)
    }

    // MARK: - Frame update

    func update(dt rawDt: CGFloat) {
        guard !config.paused else { return }
        let dt = min(rawDt, 1.0 / 30.0)
        t += dt

        trackCursorMotion(dt: dt)
        updateEmote(dt: dt)
        updateBlink(dt: dt)

        if mode != .airborne { landing = nil; landingReach = 0 }
        if mode != .attached { runNose = approach(runNose, 0, 8, dt) }
        switch mode {
        case .attached: updateAttached(dt: dt)
        case .airborne: updateAirborne(dt: dt)
        case .dangling: updateDangling(dt: dt)
        case .held:     updateHeld(dt: dt)
        case .nesting:  updateNesting(dt: dt)
        }

        updateWeb(dt: dt)
        updatePrey(dt: dt)
        updateLook(dt: dt)
        updateLegs(dt: dt)

        // Rest the pointer on it for a moment and it tells you its name.
        let hovering = cursor.distance(to: pos) < grabRadius * 1.15 && cursorVel.length < 30 && !isHeld
        hoverFor = hovering ? hoverFor + dt : 0
        nameTag.step(to: hoverFor > 0.7 || isHeld ? 1 : 0, dt: dt)
        odometer += speed * dt / max(config.scale, 0.05)

        if activity != .roll { rollSpin = 0 }
        // Rolling, it balls up — shorter along the body, and the volume rule
        // makes it correspondingly rounder.
        let balled = activity == .roll && mode == .attached && rollPhase().phase == 1
        stretch.step(to: balled ? 0.7 : 1, dt: dt)
        fatten.step(to: 1, dt: dt)
        happy.step(to: 0, dt: dt)
        startled.step(to: 0, dt: dt)
        grabbed.step(to: isHeld ? 1 : 0, dt: dt)
        updateYaw(dt: dt)
        grounded.step(to: mode == .attached ? 1 : 0, dt: dt)
        bungee.step(to: 0, dt: dt)
        webAlpha.step(to: webActive ? 1 : 0, dt: dt)
        if dragAlpha > 0 { dragAlpha = max(0, dragAlpha - dt * 1.1) }
        wagPhase += dt * (6 + wag.value * 4)

        // Volume preservation: fattening follows stretch inversely — except
        // balled up for a roll, where it pulls in all round.
        let s = stretch.value
        fatten.value = lerp(fatten.value, balled ? 0.96 : 1 / max(0.6, s), 0.35)

        // Heading spring, on the shortest way round.
        let err = angleDelta(heading, headingTarget)
        // Turning round on a thread is a slow, deliberate roll rather than
        // the snap of a landing.
        let soft: CGFloat = mode == .dangling ? (webStyle == .hang ? 0.4 : 0.7) : 1
        headingVel += (err * 190 * soft - headingVel * 21 * soft.squareRoot()) * dt
        heading += headingVel * dt

        updateRope(dt: dt)
    }

    // MARK: Food

    /// Lets something loose on the desktop for it to hunt. Ground creatures
    /// drop in onto a ledge some way off; a fly is let go in the air.
    @discardableResult
    func release(_ kind: PreyKind) -> Prey {
        let screen = map.screenFrame(containing: pos)
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
        nextPreyID += 1
        prey.append(p)
        wake()
        if mode == .attached, [.rest, .sleep, .idle, .look].contains(activity) {
            decisionIn = min(decisionIn, 0.3)
        }
        setEmote(.question, 0.8)
        return p
    }

    /// Whatever it is after: the nearest thing still loose.
    private func quarry() -> Prey? {
        guard t > huntPauseUntil else { return nil }
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
            // Held to the mouth.
            let hd = SpiderRenderer.head(for: look)
            c.pos = toWorld(V2(hd.c.x + hd.r * 0.75, hd.c.y - 7))
            c.heading = heading + (facing < 0 ? .pi : 0) + sin(t * 9) * 0.15
            c.facing = 1
        }
        prey.removeAll { $0.state == .eaten && $0.alpha <= 0 }
        fed = max(0, fed - dt / 900)
        // Lost track of it for too long: leave it be for a while.
        if huntTarget != nil, t - huntSince > 75 {
            huntTarget = nil
            huntPauseUntil = t + 25
        }
    }

    /// The hunt, one decision at a time: close in along its own ledge,
    /// stalking the last stretch, and pounce; or leap to wherever it can get
    /// nearest to; a fly in the air is snatched when it comes within range.
    private func hunt(_ p: Prey) {
        let d = p.pos - pos
        let dist = d.length
        let sc = config.scale
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
            if dist < 14 * sc {
                catchPrey(p)
            } else if abs(along) < 105 * sc, facingIt, t - lastPounceAt > 1.2 {
                pounce(at: p.mouthPoint)
            } else {
                // Close in: a sneak for the last stretch, a walk before that.
                let dir: CGFloat = along >= 0 ? 1 : -1
                let style: Activity = abs(along) < 230 * sc ? .sneak : .walk
                let speed = style == .sneak ? config.walkSpeed * 0.42 : config.walkSpeed
                turnTo(dir, then: style, for: clamp(abs(along) / max(speed, 1) * 0.8, 0.4, 3.0))
            }
            return
        }
        // Somewhere else: leap to the spot nearest it that it can reach.
        var best: (d: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) {
            let dp = spot.point.distance(to: p.pos)
            guard spot.point.distance(to: pos) > 50, dp < dist - 30 else { continue }
            guard ballistic(from: pos, to: spot.point) != nil else { continue }
            if best == nil || dp < best!.d { best = (dp, spot.point) }
        }
        if let b = best, abs(along) < 260 * sc || chance(0.5) {
            startJump(to: b.point)
        } else {
            walkToward(p.pos)
        }
    }

    private func pounce(at point: V2) {
        lastPounceAt = t
        huntPounce = true
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
        let mouth = toWorld(V2(hd.c.x + hd.r * 0.7, hd.c.y - 5))
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
        if mode == .dangling {
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
            yaw = turnFromYaw * cos(u * .pi)
            if (yaw < 0) != (turnFromYaw < 0) && facing != pendingDir {
                facing = pendingDir
                walkDir = pendingDir
                turned = true
            }
        } else if mode == .dangling && webStyle == .swing {
            yaw = approach(yaw, facing, 9, dt)
        } else if mode == .dangling {
            // Twisting slowly on the line, showing its face as it comes round;
            // a twirl whips it round several times.
            let rate: CGFloat = t < twirlUntil ? 4.5 : 0.55
            let spin = cos(t * rate)
            yaw = approach(yaw, spin * 1.0, t < twirlUntil ? 14 : 6, dt)
            facing = yaw >= 0 ? 1 : -1
        } else if mode == .nesting {
            yaw = approach(yaw, facing, 6, dt)
        } else {
            // A glance turns it part-way toward you without changing which
            // way it faces along the ledge.
            let g = activity == .glance ? 0.62 : glance
            yaw = approach(yaw, facing * (1 - g), 9, dt)
        }
        if (yaw >= 0) != (before >= 0) {
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
                legs[i] = a
                legs[j] = b
            }
        }
    }

    private var mirrorSign: CGFloat { yaw >= 0 ? 1 : -1 }

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
    private func groundFoot(_ local: V2) -> V2 {
        guard mode == .attached, let snapped = map.snapToEdge(toWorld(local), loopID: anchor.loopID) else {
            return local
        }
        return toLocal(snapped)
    }

    private func trackCursorMotion(dt: CGFloat) {
        let d = cursor - prevCursor
        prevCursor = cursor
        if dt > 0 { cursorVel = approach(cursorVel, d / dt, 18, dt) }

        // Petting: quick back-and-forth right on top of the spider.
        let near = cursor.distance(to: pos) < 40 * config.scale
        if near && d.length > 1.2 {
            let sign: CGFloat = d.x >= 0 ? 1 : -1
            if sign != lastPetSign {
                lastPetSign = sign
                pettingScore = min(pettingScore + 0.42, 1.6)
            }
        }
        pettingScore = max(0, pettingScore - dt * 0.55)
        if pettingScore > 0.85 {
            happy.value = max(happy.value, 0.85)
            if emote == .none { setEmote(.hearts, 1.0) }
            if mode == .attached, activity != .wiggle, activity != .dance, chance(dt * 1.5) {
                beginActivity(chance(0.6) ? .wiggle : .dance, dur: 0.9)
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
        decisionIn -= dt * config.liveliness
        restedFor = (activity == .rest || activity == .sleep) ? restedFor + dt : 0
        progressActivity(dt: dt)
        // On a hunt nothing else is allowed to run long: a walk toward the
        // prey is re-aimed every second or so, and idle habits are dropped.
        if caught == nil, huntTarget != nil, prey.contains(where: { $0.id == huntTarget && $0.state == .loose }) {
            let hunting: Set<Activity> = [.walk, .sneak, .scurry, .look, .turn, .crouch, .idle, .startle, .shake]
            if !hunting.contains(activity) { queued = nil; finishActivity() }
            else if [.walk, .sneak, .scurry].contains(activity), activityTime > 1.0 { activityDur = min(activityDur, activityTime) }
        }
        if activityTime > activityDur { finishActivity() }
        if activity == .idle && decisionIn <= 0 { think() }

        // Something has slid in front of where it is standing, or it has been
        // pushed off the screen: get out of the way.
        let covered = map.seg(anchor).map { !$0.isOpen(at: anchor.t) } ?? true
        let bodyCovered = !map.isVisible(pos, depth: loop.depth)
        if covered || bodyCovered || !map.isOnScreen(here.pos, slack: 20) {
            occludedFor += dt
            if occludedFor > 0.05, t > escapeUntil { escapeOcclusion() }
        } else {
            occludedFor = 0
        }

        // Posture targets for whatever it is doing.
        let post = posture()
        targetSpeed = config.walkSpeed * post.speed * bout
        lift.step(to: post.lift * config.scale, dt: dt)
        pitch.step(to: post.pitch, dt: dt)
        crouch.step(to: post.crouch, dt: dt)
        wag.step(to: post.wag, dt: dt)
        lid.step(to: post.lid, dt: dt)
        legMode = post.legsFree ? .free : .planted
        sleepiness.step(to: activity == .sleep ? 1 : 0, dt: dt)

        // Slow down through corners so the turn reads.
        let turning = abs(angleDelta(heading, headingTarget))
        let turnFactor = remap(turning, 0.25, 1.2, 1.0, 0.45)
        speed = approach(speed, targetSpeed * turnFactor, 7, dt)

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
        runNose = -0.05 * speedFrac

        gaitPhase += speed / (boutStride * config.scale) * dt
        if gaitPhase > 1 { gaitPhase -= gaitPhase.rounded(.down) }

        // Body follows the anchor with a little lag, so moving windows drag it.
        if !anchorValid { anchorPos = here.pos; anchorValid = true }
        anchorPos = approach(anchorPos, here.pos, 45, dt)

        // Walking bob: a small rise and fall twice a cycle, plus a sway along
        // the direction of travel once a cycle. The planted feet stay put, so
        // the legs flex against it. Breathing when still.
        // One gentle rise per step (two steps a cycle), not a buzz.
        let bobAmp = speedFrac * 1.0 * boutBob * config.scale
        let bob = sin(gaitPhase * 4 * .pi) * bobAmp * 0.5 + sin(gaitPhase * 2 * .pi) * bobAmp * 0.3
        let sway = cos(gaitPhase * 2 * .pi) * bobAmp * 0.3
        let breathe = bodyWobble.value(t * (activity == .sleep ? 0.6 : 1.0))
            * (activity == .sleep || activity == .rest ? 1.1 : 0.45) * config.scale
        pos = anchorPos + here.normal * (bob + lift.value + breathe) + here.tangent * sway

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

    static let rollRadius: CGFloat = 16
    static let rollFraction: CGFloat = 0.6
    /// The roll in three parts: 0 winding up, 1 rolling, 2 landing out of
    /// it — and how far through that part it is.
    private func rollPhase() -> (phase: Int, v: CGFloat) {
        let u = activityDur > 0 ? clamp(activityTime / activityDur, 0, 1) : 1
        let windup: CGFloat = 0.22
        let roll = Spider.rollFraction
        if u < windup { return (0, u / windup) }
        if u < windup + roll { return (1, (u - windup) / roll) }
        return (2, (u - windup - roll) / max(1 - windup - roll, 0.01))
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
            switch gaitStyle {
            case .normal: break
            case .bouncy: p.lift = 2
            case .tiptoe: p.lift = 3.5; p.speed *= 0.8
            case .lumber: p.lift = -1.5; p.speed *= 0.7; p.wag = 0.5
            }
        case .sneak:
            p.speed = 0.42
            p.crouch = 0.4
            p.pitch = -0.08
        case .scurry:
            p.speed = 2.6
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
            switch r.phase {
            case 0:
                p.crouch = 0.55 * r.v
                p.pitch = 0.2 * r.v
                p.lift = -2 * r.v
                p.legsFree = false
            case 1:
                // Balled up, its middle sits one radius off the ledge.
                p.lift = -4
                p.legsFree = true
                // A bell of speed that covers one circumference in the roll.
                let circumference = 2 * .pi * Spider.rollRadius * config.scale
                let peak = (.pi / 2) * circumference / (Spider.rollFraction * max(activityDur, 0.3)) * 1.12
                p.speed = peak / max(config.walkSpeed, 1) * sin(r.v * .pi)
            default:
                p.lift = -4 + 4 * r.v
                p.crouch = 0.4 * (1 - r.v)
                p.legsFree = false
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
            if activityTime > activityDur { launchPendingJump() }
        case .shoot:
            // The line races out to its mark, then it lets go of the ledge.
            shotProgress = clamp(activityTime / max(activityDur - 0.05, 0.05), 0, 1)
            if activityTime > activityDur {
                if shotPurpose == .climb { climbOutOnLine() } else { launchSwing() }
            }
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
                rollSpin = 0
                rollTravel = 0
                rollLanded = false
            case 1:
                rollTravel += speed * dt
                rollSpin = -min(rollTravel / (Spider.rollRadius * config.scale), 2 * .pi)
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
            if t - lastUserActivity > lerp(60, 10, personality.laziness), restedFor > 6,
               chance(dt * lerp(0.06, 0.4, personality.laziness)) {
                beginActivity(.sleep, dur: randRange(15, 45))
            }
        case .sleep:
            if !fullScreenApp, cursor.distance(to: pos) < 90 * config.scale && cursorVel.length > 40 {
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
        activity = a
        activityTime = 0
        activityDur = dur
        turned = false
        if a == .turn {
            turnFromYaw = yaw >= 0 ? 1 : -1
            turnGait = 0
            if pendingDir == walkDir { pendingDir = -walkDir }
        }

        if a == .wave || a == .groom || a == .wiggle { happy.value = max(happy.value, 0.35) }
        if a == .sleep { setEmote(.zzz, dur) }
        if a == .wiggle && emote == .none { setEmote(.note, min(dur, 1.0)) }
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

    private func onLedgeEnd() {
        if caught == nil, huntTarget != nil {
            // Mid-hunt: no sightseeing, just decide again from here.
            activity = .idle
            activityTime = 0
            decisionIn = 0
            return
        }
        let roll = CGFloat.random(in: 0...1)
        if roll < 0.3, let spot = bestJumpSpot(from: pos, exclude: anchor.loopID) {
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
            // edge — or the end of it — stops it.
            let lim = seg.limit(from: anchor.t, dir: walkDir)
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
            guard next.isOpen(at: entryT + (walkDir > 0 ? 0.5 : -0.5)) else {
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
        guard config.followCursor, !fullScreenApp else { return }
        let d = cursor.distance(to: pos)
        let busy = [.startle, .crouch, .turn, .sleep, .curious, .stretch, .shake, .roll, .spin, .armsUp, .shoot].contains(activity)

        // Startled by a fast swipe nearby. A brave spider takes more
        // startling, and stands its ground when it is.
        let brave = personality.bravery
        let startleSpeed = lerp(450, 1700, brave)
        let startleRange = lerp(90, 45, brave) * config.scale
        if !busy && startled.value < 0.2 && d < startleRange && cursorVel.length > startleSpeed {
            beginActivity(.startle, dur: 0.5)
            queued = nil
            startled.velocity = 13
            setEmote(.surprise, 0.6)
            if chance(lerp(0.9, 0.15, brave)) { fleeFromCursor() }
            return
        }

        // A pointer hovering close by is interesting.
        let curiousGap = lerp(20, 4, personality.curiosity)
        if !busy && d < 110 * config.scale && d > 36 * config.scale && cursorVel.length < 60
            && t - lastCurious > curiousGap && (activity == .idle || activity == .look || activity == .walk) {
            lastCurious = t
            if chance(0.25 + personality.playfulness * 0.2) {
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

        // Keeping out of the way of a full-screen app: sleep in the hammock,
        // or failing that in a bottom corner, and stay there.
        if fullScreenApp, homing == nil {
            if hasHammock {
                goHome(.sleep)
            } else if pos.distance(to: hideawaySpot()) < 40 * config.scale {
                beginActivity(.sleep, dur: randRange(40, 90))
            } else {
                goHome(.corner)
            }
            return
        }

        // Somewhere to be: heading for the hammock, to build it or to sleep.
        if homing != nil {
            if t - homingSince > 120 { homing = nil } else { pursueHome(); return }
        }

        // Something to eat about: everything else can wait.
        if caught == nil, let q = quarry() {
            decisionIn = randRange(0.25, 0.7) / max(config.liveliness, 0.25)
            hunt(q)
            return
        }

        // Left alone, it settles down and eventually nods off. The lazy ones
        // do not wait to be left alone — and if it has a hammock, that is
        // where it goes.
        if idleFor > lerp(120, 20, P.laziness), chance(lerp(0.1, 0.6, P.laziness)) {
            if let h = hammock, h.progress >= 1, chance(0.7) {
                goHome(.sleep)
                return
            }
            beginActivity(.rest, dur: randRange(8, 20) * (0.7 + P.laziness))
            return
        }

        if config.followCursor, dCursor < 340, chance(lerp(0.1, 0.65, P.curiosity)) {
            // Investigate the pointer.
            if dCursor > 70 {
                walkToward(cursor)
            } else {
                beginActivity(.look, dur: randRange(0.8, 2.0))
            }
            return
        }

        // Everything else is a weighted draw. Each weight is the plain
        // frequency scaled by whichever trait it expresses, so a shy spider
        // still dances now and then and a show-off still rests.
        let play = lerp(0.25, 2.2, P.playfulness)
        let love = lerp(0.2, 2.2, P.affection)
        let lazy = lerp(0.3, 2.4, P.laziness)
        let busy = lerp(0.5, 1.6, P.energy)
        var options: [(CGFloat, () -> Void)] = []
        options.append((30 * busy, {
            let dir: CGFloat = chance(0.7) ? self.walkDir : -self.walkDir
            let sneaky = lerp(0.3, 0.05, P.bravery)
            let hurried = lerp(0.04, 0.22, P.energy)
            let style: Activity = chance(sneaky) ? .sneak : (chance(hurried) ? .scurry : .walk)
            let dur = style == .scurry ? randRange(0.5, 1.2) : randRange(1.4, 5.0)
            self.turnTo(dir, then: style, for: dur)
        }))
        options.append((10, { self.beginActivity(.look, dur: randRange(0.7, 2.2)) }))
        options.append((6 * lazy, { self.beginActivity(.rest, dur: randRange(3, 8)) }))
        options.append((6, { self.beginActivity(.groom, dur: randRange(1.4, 2.8)) }))
        options.append((6 * (0.5 + busy * 0.5), { self.beginActivity(.fidget, dur: randRange(0.7, 1.2)) }))
        options.append((4, { self.beginActivity(.scratch, dur: randRange(1.0, 1.6)) }))
        options.append((2 * love, {
            self.beginActivity(.wave, dur: 1.5)
            self.happy.velocity = 4
        }))
        options.append((2 * play, { self.beginActivity(.wiggle, dur: 0.8) }))
        options.append((3 * love, { self.beginActivity(.glance, dur: randRange(0.8, 1.6)) }))
        options.append((3 * lerp(0.4, 1.8, P.curiosity), { self.beginActivity(.peer, dur: randRange(1.2, 2.0)) }))
        options.append((2.5 * lerp(0.5, 1.5, (P.affection + P.bravery) / 2), {
            self.beginActivity(.armsUp, dur: randRange(0.9, 1.5))
            if chance(0.5) { self.setEmote(.sparkle, 0.9) }
        }))
        options.append((2 * play, {
            self.beginActivity(.roll, dur: randRange(0.8, 1.1))
            self.queue(.shake, 0.45)
        }))
        options.append((1.5 * play, {
            self.beginActivity(.dance, dur: randRange(1.2, 2.0))
            self.setEmote(.note, 1.4)
        }))
        options.append((1.5 * busy, { self.beginActivity(.pushup, dur: randRange(1.2, 1.8)) }))
        options.append((1.5 * (0.5 + lazy * 0.5), { self.beginActivity(.legStretch, dur: 1.6) }))
        options.append((1 * play, { self.beginActivity(.spin, dur: 0.1) }))
        options.append((2, { self.turnTo(-self.walkDir, then: .look, for: randRange(0.6, 1.4)) }))
        options.append((8 * lerp(0.15, 2.0, self.gait.jumpiness), {
            if let spot = self.bestJumpSpot(from: self.pos, exclude: self.anchor.loopID) {
                self.startJump(to: spot.point)
            } else {
                self.turnTo(chance(0.5) ? 1 : -1, then: .walk, for: randRange(1.2, 3.0))
            }
        }))
        options.append((8 * lerp(0.1, 2.0, self.gait.webbiness), {
            if self.config.webs, self.canRappel() {
                self.dropOnWeb()
            } else {
                self.beginActivity(.walk, dur: randRange(1.2, 3.0))
            }
        }))
        // Swinging off on a line, if there is something up ahead to hang it from.
        options.append((7 * lerp(0.1, 2.2, self.gait.webbiness) * lerp(0.6, 1.4, P.playfulness), {
            if self.config.webs, self.startSwing() { return }
            self.beginActivity(.look, dur: randRange(0.6, 1.2))
        }))
        // Spinning a retreat, once, when it has been about for a while.
        if config.webs, hammock == nil, t > 45 {
            options.append((1.6 * lerp(0.3, 1.8, self.gait.webbiness) * lerp(0.6, 1.6, P.laziness), {
                self.goHome(.build)
            }))
        }
        if let h = hammock, h.progress >= 1 {
            options.append((1.5 * lerp(0.2, 2.5, P.laziness), { self.goHome(.sleep) }))
        }

        let total = options.reduce(0) { $0 + $1.0 }
        var pick = randRange(0, total)
        for (w, act) in options {
            pick -= w
            if pick <= 0 { act(); return }
        }
        options.last?.1()
    }

    /// On its own it only pays out silk from something it is hanging under; if
    /// you ask for it, anywhere with room to descend will do.
    private func canRappel(userAsked: Bool = false) -> Bool {
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

    private func fleeFromCursor() {
        guard let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count else { return }
        let seg = loop.segs[anchor.segIdx]
        let away = (pos - cursor).dot(seg.dir)
        let dir: CGFloat = away >= 0 ? 1 : -1
        // No time for a tidy turn when scared: spin round and go.
        if dir != walkDir {
            walkDir = dir
            facing = dir
        }
        queue(.scurry, randRange(0.5, 1.1))
    }

    /// A window has come over it: get out from under, at once. It fires a
    /// line straight up and climbs to whatever is above, or simply lets go
    /// and drops; failing both, it leaps for the nearest clear spot.
    private func escapeOcclusion() {
        occludedFor = 0
        escapeUntil = t + 2.0
        queued = nil
        pendingJump = nil
        wake()
        startled.velocity = 6
        setEmote(.surprise, 0.5)
        let screen = map.screenFrame(containing: pos)
        let roomBelow = pos.y - screen.minY > 70
        let ceiling = config.webs ? map.ceiling(above: pos, maxRise: 900) : nil
        // Clear if nothing sits over the line's path just under that edge.
        let ceilingClear = ceiling.map { map.isVisible($0 - V2(0, 4), depth: Int.max) } ?? false
        if ceilingClear, let c = ceiling, !roomBelow || chance(0.6) {
            // Up and out: a line to the ceiling, then hand over hand to the top.
            shotTarget = c
            shotPurpose = .climb
            shotProgress = 0
            beginActivity(.shoot, dur: 0.2)
        } else if roomBelow {
            detachAndFall()
        } else if let spot = bestJumpSpot(from: pos, exclude: anchor.loopID) {
            startJump(to: spot.point)
        } else if let spot = map.nearestSpot(to: pos, within: 900) {
            startJump(to: spot.point)
        } else {
            detachAndFall()
        }
    }

    /// The line fired straight up has caught: haul up it to the surface.
    private func climbOutOnLine() {
        attachWeb(at: shotTarget)
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
        guard let point = pendingJump, let launch = ballistic(from: pos, to: point) else {
            pendingJump = nil
            activity = .idle
            crouch.velocity = -6
            return
        }
        pendingJump = nil
        launchLoop = anchor.loopID
        mode = .airborne
        air = .jump
        airTime = 0
        noAttachFor = 0.1
        vel = launch
        if let spot = map.nearestSpot(to: point, within: 40 * config.scale) {
            landing = (spot.point, spot.seg.angle, spot.seg.dir)
        }
        crouch.velocity = -9
        stretch.velocity = 5
        wag.reset(0)
        legMode = .free
        beginDragline(from: pos)
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

    private func beginDragline(from p: V2) {
        guard config.webs else { return }
        dragFrom = p
        dragAlpha = 0.9
    }

    private func bestJumpSpot(from p: V2, exclude: String) -> (anchor: Anchor, point: V2)? {
        let spots = map.sampleSpots(spacing: 40)
        guard !spots.isEmpty else { return nil }
        var scored: [(CGFloat, Anchor, V2)] = []
        let playful = config.followCursor && cursor.distance(to: p) < 700
        for s in spots {
            let d = s.point.distance(to: p)
            guard d > 70, d < 680 else { continue }
            var score = s.loop.kind.appeal
            score *= remap(d, 70, 680, 1.25, 0.45)
            if s.loop.id == exclude { score *= 0.18 }
            if s.loop.id == anchor.loopID { score *= 0.3 }
            if playful {
                let dc = s.point.distance(to: cursor)
                score *= remap(dc, 0, 500, 1.9, 0.9)
            }
            guard ballistic(from: p, to: s.point) != nil else { continue }
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

        // Fly head-first: mirror to face the direction of travel, pitch into
        // the arc, but never roll past 50 degrees or it reads as tumbling.
        var flightHeading: CGFloat?
        if vel.length > 60 {
            facing = vel.x >= 0 ? 1 : -1
            let pitchAngle = angleDelta(0, vel.angle + (vel.x < 0 ? .pi : 0))
            flightHeading = clamp(pitchAngle, -0.85, 0.85)
            if air == .thrown { flightHeading! += sin(t * 9) * 0.18 }
        }
        // Coming in to land: over the last stretch it turns to meet the
        // surface — feet first, even upside down under a window — and the
        // legs reach out for it, so touchdown is the end of a movement
        // rather than a snap. A leap knows where it is going; a fall or a
        // throw looks ahead for whatever it is about to hit.
        landingReach = 0
        var aim = landing
        if aim == nil, noAttachFor <= 0, vel.length > 40,
           let spot = map.nearestSpot(to: pos + vel * 0.12, within: 70 * config.scale,
                                      excluding: airTime < 0.28 ? launchLoop : nil) {
            aim = (spot.point, spot.seg.angle, spot.seg.dir)
        }
        if let a = aim {
            let to = a.point - pos
            let closing = to.dot(vel) > 0 || vel.length < 80
            let range = (landing != nil ? 130 : 70) * config.scale
            if closing { landingReach = clamp(1 - to.length / range, 0, 1) }
        }
        if landingReach > 0.001, let a = aim {
            let w = smoothstep(landingReach)
            let along = (vel.length > 30 ? vel : a.point - pos).dot(a.dir)
            if w > 0.45 { facing = along >= 0 ? 1 : -1 }
            let fh = flightHeading ?? heading
            headingTarget = fh + angleDelta(fh, a.angle) * w
        } else if let fh = flightHeading {
            headingTarget = fh
        }
        legMode = .free
        crouch.step(to: 0, dt: dt)
        lift.step(to: 0, dt: dt)
        pitch.step(to: 0, dt: dt)
        wag.step(to: 0, dt: dt)
        lid.step(to: 0, dt: dt)

        // A pounce: the fangs get whatever they pass.
        if huntPounce { snapAtPrey(reach: 6) }

        bounceOffScreens()

        if noAttachFor <= 0 {
            if let spot = map.nearestSpot(to: pos, within: 18 * config.scale,
                                          excluding: airTime < 0.28 ? launchLoop : nil) {
                // Only grab on if we are moving toward the surface, or slow enough.
                let toward = (spot.point - pos).normalized.dot(vel.normalized)
                if vel.length < 260 || toward > -0.25 {
                    land(on: spot.anchor, seg: spot.seg)
                    return
                }
            }
        }

        // Web rescue: fire a line if we are falling with nothing below. Never
        // during a leap — it is aimed at something, and cutting it short with a
        // dangle reads as the spider changing its mind mid-air. A jump that has
        // been going for well over its flight time has already failed, though.
        if config.webs, air != .jump || airTime > 1.5 {
            let fallingLong = airTime > 0.55 && vel.y < 40
            let aboutToLeave = pos.y < map.worldBounds.minY + 60 && vel.y < 0
            if (fallingLong && chance(dt * 2.2)) || aboutToLeave {
                if let c = map.ceiling(above: pos, maxRise: 720) {
                    attachWeb(at: c)
                    return
                }
            }
        }

        // Off the world entirely: put it back at the top of the main screen.
        if !map.worldBounds.insetBy(dx: -400, dy: -400).contains(pos.point) {
            let f = NSScreen.main?.frame ?? map.worldBounds
            pos = V2(f.midX + randRange(-200, 200), f.maxY - 60)
            vel = V2(0, -50)
        }
    }

    private func bounceOffScreens() {
        let f = map.screenFrame(containing: pos)
        let pad = 14 * config.scale
        var bounced = false
        if pos.x < f.minX + pad, vel.x < 0 {
            pos.x = f.minX + pad; vel.x = -vel.x * 0.52; vel.y *= 0.88; bounced = true
        }
        if pos.x > f.maxX - pad, vel.x > 0 {
            pos.x = f.maxX - pad; vel.x = -vel.x * 0.52; vel.y *= 0.88; bounced = true
        }
        if pos.y > f.maxY - pad, vel.y > 0 {
            pos.y = f.maxY - pad; vel.y = -vel.y * 0.45; vel.x *= 0.9; bounced = true
        }
        if pos.y < f.minY + pad, vel.y < 0 {
            pos.y = f.minY + pad; vel.y = -vel.y * 0.5; vel.x *= 0.86; bounced = true
        }
        if bounced {
            stretch.velocity = 6
            if abs(vel.x) + abs(vel.y) < 120 {
                if let spot = map.nearestSpot(to: pos, within: 90) {
                    land(on: spot.anchor, seg: spot.seg)
                }
            }
        }
    }

    private func land(on a: Anchor, seg: Seg) {
        let impact = min(vel.length, 1400)
        hurrying = false
        mode = .attached
        anchor = a
        lastLoopRect = nil
        walkDir = vel.dot(seg.dir) >= 0 ? 1 : -1
        if abs(vel.dot(seg.dir)) < 20 { walkDir = chance(0.5) ? 1 : -1 }
        // Keep the body where it actually is and let it glide the last few
        // points onto the ledge, rather than snapping there.
        anchorPos = pos
        anchorValid = true
        legFramePos = pos
        vel = .zero
        speed = 0
        // Stand on the ledge, facing the way it was going. The heading is left
        // to its spring, so the body swings down onto the surface rather than
        // snapping to it; the feet ease in from wherever they were.
        headingTarget = seg.angle
        facing = walkDir
        travelLocal = V2(1, 0)
        legMode = .planted
        // Splat onto the ledge, then spring back up.
        stretch.velocity = remap(impact, 100, 1200, 3, 12)
        crouch.velocity = remap(impact, 100, 1200, 2, 8)
        for i in legs.indices {
            legs[i].footVel = .zero
            legs[i].swinging = false
        }
        detachWeb(fade: true)
        pendingJump = nil
        queued = nil
        // A beat to get its feet under it before it decides anything.
        beginActivity(.idle, dur: 0.3)
        decisionIn = randRange(0.4, 1.0)
        if huntPounce {
            huntPounce = false
            snapAtPrey(reach: 14)
            if caught == nil { decisionIn = 0.15 }
        }
        if let c = caught, c.state == .caught, activity != .eat {
            // Landed with the catch: settle down to it.
            beginActivity(.eat, dur: c.kind.mealTime * randRange(0.9, 1.15))
        }
        if impact > 800 {
            setEmote(.surprise, 0.5)
            beginActivity(.shake, dur: 0.5)
        }
    }

    private func detachAndFall() {
        lastLoopRect = nil
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
    }

    // MARK: Dangling

    private func updateDangling(dt: CGFloat) {
        webGrace = max(0, webGrace - dt)

        // Keep the pendulum on the display: never pay out more thread than
        // there is room below the anchor, and never swing so wide it leaves
        // the sides.
        let screen = map.screenFrame(containing: webAnchor)
        let margin = 30 * config.scale
        let maxLen = max(40, webAnchor.y - (screen.minY + margin))
        webLenTarget = min(webLenTarget, maxLen)
        webLen = min(webLen, maxLen)

        let swinging = webStyle == .swing
        let maxSwing: CGFloat = swinging ? 1.5 : 1.1
        if abs(webAngle) > maxSwing {
            webAngle = clamp(webAngle, -maxSwing, maxSwing)
            webAngleVel *= -0.35
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
        let damping: CGFloat = swinging ? 0.22 : 1.6
        let len = max(webLen + bungee.value, 20)
        let acc = -(g / len) * sin(webAngle) - webAngleVel * damping
        webAngleVel += acc * dt
        webAngle += webAngleVel * dt
        // Bouncing on the line stretches the body with it.
        stretch.value += bungee.velocity * 0.00025

        let dir = V2(sin(webAngle), -cos(webAngle))
        let newPos = webAnchor + dir * len
        if dt > 0 { vel = (newPos - pos) / dt }
        pos = newPos

        // Sideways off the screen: the line snags and it swings back.
        if pos.x < screen.minX + margin || pos.x > screen.maxX - margin {
            webAngleVel = -webAngleVel * 0.5
            webAngle += webAngleVel * dt * 2
        }

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
        if abs(moved) < 40 {
            climbTravel += abs(moved) / (Spider.climbStride * config.scale)
            climbDir = approach(climbDir, clamp(-moved / dt / 60, -1, 1), 8, dt)
        }

        if swinging {
            hangHeadUp = false
            updateSwing(dt: dt, alongThread: alongThread, len: len)
            return
        }
        // Climbing, it turns to face up the line and hauls; once it stops it
        // lets itself back round to hang head down.
        let hauling = webLenTarget < webLen - 3
        stillFor = hauling ? 0 : stillFor + dt
        if hauling { hangHeadUp = true } else if stillFor > 0.5 { hangHeadUp = false }
        let headDir = hangHeadUp ? alongThread + .pi : alongThread
        headingTarget = headDir + (facing < 0 ? .pi : 0) + sin(t * 1.3) * 0.03
        wag.step(to: t < twirlUntil ? 0.8 : 0, dt: dt)

        // A window has come over it on the line: straight up and out.
        if !map.isVisible(pos, depth: Int.max) {
            webLenTarget = 26
            decisionIn = max(decisionIn, 1.0)
            twirlUntil = 0
        }

        // Curious about a pointer below it: pays out line to come and see.
        if config.followCursor, cursorVel.length < 40, cursor.y < webAnchor.y - 60,
           abs(cursor.x - webAnchor.x) < 120 * config.scale, t - lastUserActivity < 6 {
            let want = clamp(webAnchor.y - cursor.y - 48 * config.scale, 30, maxLen)
            webLenTarget = approach(webLenTarget, want, 1.5, dt)
        }

        decisionIn -= dt * config.liveliness
        if decisionIn <= 0 { thinkOnWeb() }

        guard webGrace <= 0 else { return }

        // Reached the ceiling: climb on.
        if webLen < 34, let spot = map.nearestSpot(to: pos, within: 40) {
            land(on: spot.anchor, seg: spot.seg)
            return
        }
        // Touched down on something below while barely swinging.
        if abs(webAngleVel) < 0.7, abs(bungee.velocity) < 40,
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
        // It turns to look the way it is going, but only once it is properly
        // going that way, so it does not flicker at the ends of the arc.
        if abs(vel.x) > 90 { facing = vel.x >= 0 ? 1 : -1 }
        let lag = clamp(-webAngleVel * 0.10, -0.22, 0.22)
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
        if swingHalfSwings > 7 || (swingHalfSwings >= 2 && abs(webAngleVel) < 0.35 && abs(webAngle) < 0.15) {
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
        beginDragline(from: pos)
        stretch.velocity = 3
        if chance(0.5) { setEmote(.sparkle, 0.7) }
        happy.velocity = 5
    }

    /// Looks for something up ahead to hang a line from, and if there is
    /// one, takes aim. Returns false if there is nowhere to swing to.
    private func startSwing() -> Bool {
        guard mode == .attached, let loop = map.loop(anchor.loopID),
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
        legMode = .free
        anchorValid = false
        activity = .idle
        queued = nil
        webGrace = 0.5
        decisionIn = 99
        stretch.velocity = 4
        happy.velocity = 3
    }

    private func thinkOnWeb() {
        decisionIn = randRange(1.4, 3.4) / max(config.liveliness, 0.25)
        if debugCalm { decisionIn = 99; return }
        let roll = CGFloat.random(in: 0...1)
        let play = personality.playfulness
        if roll < 0.2 {
            // A shift of its weight sets it swaying gently.
            webAngleVel += randRange(-0.18, 0.18)
            happy.velocity = 3
        } else if roll < 0.32 {
            // Spin slowly to face the other way.
            facing = -facing
        } else if roll < 0.42 + play * 0.1 {
            // Bounces on the line like it is elastic.
            bungee.velocity = randRange(180, 320) * (chance(0.5) ? 1 : -1)
            if chance(0.5) { setEmote(.note, 1.0) }
            happy.velocity = 4
        } else if roll < 0.5 + play * 0.1 {
            // A twirl.
            twirlUntil = t + randRange(1.4, 2.4)
            setEmote(.sparkle, 1.2)
        } else if roll < 0.62 {
            webLenTarget = clamp(webLen + randRange(60, 220), 30, 780)
        } else if roll < 0.8 {
            webLenTarget = clamp(webLen - randRange(60, 260), 30, 780)
        } else if roll < 0.86 + play * 0.08, webLen > 90 {
            workUpSwing()
        } else if roll < 0.92, let spot = bestJumpSpot(from: pos, exclude: ""),
                  let launch = ballistic(from: pos, to: spot.point) {
            detachWeb(fade: true)
            mode = .airborne
            air = .jump
            airTime = 0
            noAttachFor = 0.08
            beginDragline(from: pos)
            vel = launch
        } else {
            setEmote(chance(0.5) ? .sparkle : .none, 0.7)
        }
    }

    private func attachWeb(at p: V2) {
        webAnchor = p
        webActive = true
        let r = pos - p
        webLen = max(28, r.length)
        webLenTarget = min(webLen + randRange(0, 120), 780)
        webAngle = atan2(r.x, -r.y)
        let tangent = V2(-r.y, r.x).normalized
        webAngleVel = vel.dot(tangent) / max(webLen, 1)
        mode = .dangling
        legMode = .free
        stretch.velocity = -3
        decisionIn = randRange(0.8, 2.0)
        webGrace = 0.5
        dragAlpha = 0
        bungee.reset(0)
        prevHangLen = webLen
        climbTravel = 0
        hangHeadUp = false
        stillFor = 0
        // Caught at speed, the line becomes a swing rather than a stop.
        if abs(vel.x) > 320 && webLen > 90 {
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
        if let loop = map.loop(anchor.loopID), anchor.segIdx < loop.segs.count {
            a = pos - loop.segs[anchor.segIdx].normal * map.standoff
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
        legMode = .free
        queued = nil
        decisionIn = randRange(1.0, 2.2)
        webGrace = 0.9
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
        h.bed + V2(0, 9 * config.scale)
    }

    /// Set off for the hammock. Building one first picks the nearer corner.
    private func goHome(_ goal: HomeGoal) {
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
        h.progress = max(h.progress, 0.02)
        hammock = h
        mode = .nesting
        nestPhase = .building
        nestTime = 0
        nestDur = randRange(7, 10)
        nestAngle = h.left ? -0.3 : .pi + 0.3
        legMode = .free
        anchorValid = false
        detachWeb(fade: true)
        queued = nil
        activity = .idle
        wag.velocity = 3
    }

    private func enterNest() {
        guard hammock != nil else { return }
        mode = .nesting
        nestPhase = .sleeping
        nestTime = 0
        nestDur = randRange(20, 50) * (0.6 + personality.laziness)
        nestZzzIn = 1.5
        legMode = .free
        anchorValid = false
        detachWeb(fade: true)
        queued = nil
        activity = .idle
        facing = hammock!.left ? 1 : -1
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
        let centre = nestCentre(h)
        wagPhase += dt * 4
        switch nestPhase {
        case .building:
            // Circles the corner laying silk, abdomen going, until the sac
            // is finished.
            let u = clamp(nestTime / nestDur, 0, 1)
            h.progress = max(h.progress, u)
            hammock = h
            // Back and forth along the sling, wall to ceiling and back,
            // laying a strand each way.
            nestAngle += dt * 1.1
            let uu = 0.5 - 0.5 * cos(nestAngle)
            let target = h.point(at: uu) + V2(0, 12 * config.scale)
            pos = approach(pos, target, 9, dt)
            let along = h.tangent(at: uu)
            let goingOut = sin(nestAngle) >= 0
            facing = (goingOut ? along.x : -along.x) >= 0 ? 1 : -1
            headingTarget = (goingOut ? along : -along).angle + (facing < 0 ? .pi : 0)
            wag.step(to: 1.3, dt: dt)
            lift.step(to: 0, dt: dt)
            pitch.step(to: -0.1, dt: dt)
            crouch.step(to: 0.1, dt: dt)
            lid.step(to: 0, dt: dt)
            sleepiness.step(to: 0, dt: dt)
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
        case .sleeping:
            // Curled up in the sac.
            // Lying along the sling, in the sag.
            pos = approach(pos, centre + V2(0, bodyWobble.value(t * 0.4) * 1.5), 5, dt)
            let along = h.tangent(at: 0.5)
            facing = h.left ? 1 : -1
            headingTarget = (facing > 0 ? along : -along).angle + (facing < 0 ? .pi : 0) + sin(t * 0.7) * 0.02
            sleepiness.step(to: 1, dt: dt)
            lid.step(to: 1, dt: dt)
            crouch.step(to: 0.35, dt: dt)
            lift.step(to: 0, dt: dt)
            pitch.step(to: 0.05, dt: dt)
            wag.step(to: 0, dt: dt)
            nestZzzIn -= dt
            if nestZzzIn <= 0 {
                nestZzzIn = randRange(3, 5)
                setEmote(.zzz, 2.8)
            }
            // A fast pointer right by it wakes it.
            if !fullScreenApp, cursor.distance(to: pos) < 70 * config.scale && cursorVel.length > 500 {
                leaveNest(startled: true)
                return
            }
            if nestTime > nestDur && !fullScreenApp { leaveNest(startled: false) }
        }
    }

    /// Out of the sac: onto the wall beside it, or a startled tumble.
    private func leaveNest(startled fright: Bool) {
        sleepiness.value = 0
        lid.value = 0
        wokeUp = false
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
        if let h = hammock, let spot = map.nearestSpot(to: hammockDoor(h), within: 60) {
            pos = spot.point
            vel = .zero
            land(on: spot.anchor, seg: spot.seg)
            beginActivity(.stretch, dur: 1.4)
            queue(.shake, 0.5)
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

    /// A hammock saved from last time.
    func restoreHammock(left: Bool) {
        hammock = Hammock(left: left, rect: hammockRect(left: left), progress: 1, damage: 0)
    }

    /// Re-fits the hammock to the screen after the displays change.
    func refitHammock() {
        guard var h = hammock else { return }
        h.rect = hammockRect(left: h.left)
        hammock = h
    }

    /// The pointer wiping across the sac tears it; enough wiping clears it.
    func wipeHammock(at p: V2, movement: CGFloat) {
        guard var h = hammock, h.progress > 0.05, movement > 0.5,
              h.rect.insetBy(dx: -6, dy: -6).contains(p.point) else { return }
        h.damage = min(1, h.damage + movement / 520)
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
        guard config.webs else { return }
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
            || isHeld || pettingScore > 0.4 || activity == .curious
        if huntTarget != nil || caught != nil, let q = caught ?? prey.first(where: { $0.id == huntTarget }) {
            target = (q.pos - pos).normalized * (caught != nil ? 0.5 : 1)
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
        emote = e
        emoteTime = 0
        emoteDur = dur
    }

    private func updateEmote(dt: CGFloat) {
        guard emote != .none else { return }
        emoteTime += dt
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
        case (.attached, .shoot):
            // One front leg thrown out along the line, the rest braced.
            if k == 0 && near {
                let aim = toLocal(shotTarget).normalized * 30
                return V2(max(aim.x, 10), max(aim.y, 6))
            }
            return rest + V2(k < 2 ? 2 : -2, 0)
        case (.nesting, _):
            if nestPhase == .sleeping {
                return leg.hip + reach * 0.6 + V2(0, leg.wobble.value(t * 0.5) * 0.6)
            }
            // Weaving: legs pat the silk in turn, front legs reaching out.
            let ph = t * 6 + CGFloat(k) * 1.5 + (near ? 0 : .pi)
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
                    let kick = toLocalDir(vel).clampedLength(1) * (swingPumping ? 9 : 3)
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
            // Both front legs come up and feel the air.
            if k == 0 {
                let a = t * 4 + (near ? 0 : 1.2)
                return V2(26 + sin(a) * 2.5, 6 + cos(a) * 3)
            }
            return rest
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
        case (.attached, .armsUp):
            // Both front legs straight up, swaying; second pair half raised.
            if k == 0 {
                let a = t * 3.5 + (near ? 0 : 0.9)
                return V2(14 + sin(a) * 3, 24 + cos(a * 1.3) * 2)
            }
            if k == 1 { return V2(leg.hip.x + 12, 8 + (near ? 0 : -2)) }
            return rest
        case (.attached, .roll):
            // Everything tucked in tight against the body, each leg curled
            // a little differently so the ball is not a smooth lump.
            let curl: CGFloat = 0.2 + CGFloat(k % 2) * 0.06
            return leg.hip + reach * curl + V2(near ? 1 : -1, 2.5 + CGFloat(k) * 0.4)
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

    private func updateLegs(dt: CGFloat) {
        let scale = max(config.scale, 0.05)
        for i in legBend.indices { legBend[i] = nil }
        // Sprite space is rotated by `heading` and mirrored by the sign of the
        // yaw, so undoing the body's motion means rotating back and then
        // un-mirroring.
        let m = mirrorSign
        let dTheta = angleDelta(legFrameHeading, heading) * m
        var deltaLocal = ((pos - legFramePos) / scale).rotated(by: -heading)
        deltaLocal.x *= m
        legFramePos = pos
        legFrameHeading = heading

        let profile = SpiderRenderer.profileAmount(yaw: yaw)
        let duty = Spider.swingDuty

        // A turn on the spot: the feet step round to where they stand in the
        // blended layout, in the usual tetrapod waves, each planted foot
        // holding its place until its turn to move. Two full step cycles fit
        // in a turn, so every leg re-plants twice — once toward the front view
        // and once into the new profile.
        if mode == .attached && activity == .turn {
            turnGait += dt * (2.0 / max(activityDur, 0.3))
            for i in legs.indices {
                var leg = legs[i]
                leg.footVel = .zero
                let ph = (turnGait + leg.phase).truncatingRemainder(dividingBy: 1)
                let target = groundFoot(SpiderRenderer.rig(i, profile: profile, look: look).foot)
                if ph < duty {
                    if !leg.swinging {
                        leg.swinging = true
                        leg.swingFrom = leg.foot
                    }
                    let u = clamp(ph / duty, 0, 1)
                    let base = V2.lerp(leg.swingFrom, target, easeInOutSine(u))
                    leg.lift = sin(u * .pi)
                    leg.foot = base + V2(0, leg.lift * 4.0)
                } else {
                    leg.swinging = false
                    leg.lift = approach(leg.lift, 0, 16, dt)
                    leg.foot = groundFoot(leg.foot)
                }
                legs[i] = leg
            }
            return
        }

        // Feet are free while the body is well round toward the front view;
        // a mere glance keeps them stepping.
        guard legMode == .planted, facing == m, profile > 0.45 else {
            for i in legs.indices {
                let target = poseTarget(i)
                // Soft, well-damped spring, so every pose change eases.
                let a = (target - legs[i].foot) * 200 - legs[i].footVel * 26
                legs[i].footVel += a * dt
                legs[i].foot += legs[i].footVel * dt
                legs[i].lift = approach(legs[i].lift, 0, 6, dt)
                legs[i].swinging = false
            }
            return
        }

        // Where a foot aims to touch down: half a stance ahead of its rest
        // position, so over the stance it drifts back through the rest pose.
        let landAhead = boutStride * (1 - duty) * 0.5
        let walking = speed > 1

        for i in legs.indices {
            var leg = legs[i]
            leg.footVel = .zero
            let ph = (gaitPhase + leg.phase).truncatingRemainder(dividingBy: 1)

            if walking && ph < duty {
                if !leg.swinging {
                    leg.swinging = true
                    leg.swingFrom = leg.foot
                }
                let u = clamp(ph / duty, 0, 1)
                // Land on the edge itself, wherever that is relative to the body.
                let restNow = SpiderRenderer.rig(i, profile: profile, look: look).foot
                let target = groundFoot(restNow + travelLocal * landAhead)
                let base = V2.lerp(leg.swingFrom, target, easeInOutSine(u))
                leg.lift = sin(u * .pi)
                // The foot lifts clear of the ledge on a shallow arc — higher
                // when it is being bouncy or walking on tiptoe.
                let stepHeight: CGFloat = gaitStyle == .bouncy ? 8 : (gaitStyle == .tiptoe ? 6.5 : 5)
                leg.foot = base + V2(0, leg.lift * stepHeight)
            } else {
                leg.swinging = false
                leg.lift = approach(leg.lift, 0, 16, dt)
                if walking {
                    // Stance: hold station on the ledge while the body moves.
                    leg.foot = leg.foot.rotated(by: -dTheta) - deltaLocal
                    leg.foot = groundFoot(leg.foot)
                    // Never let a foot be dragged past what the leg can reach.
                    let reach = leg.foot - leg.hip
                    let maxReach = (leg.rest - leg.hip).length * 1.4
                    if reach.length > maxReach {
                        leg.foot = groundFoot(leg.hip + reach.normalized * maxReach)
                    }
                } else {
                    // Standing: settle onto the rest pose — on the edge, which
                    // round a corner is not where the rest pose says — with a
                    // little idle shuffle so it never looks frozen.
                    var rest = SpiderRenderer.rig(i, profile: profile, look: look).foot
                    rest.x += leg.wobble.value(t * 0.8) * 0.5
                    leg.foot = approach(leg.foot, groundFoot(rest), 9, dt)
                }
            }
            legs[i] = leg
        }
    }

    // MARK: - Debug

    /// Tools only: no decisions of its own while on the line, so a film can
    /// hold it there.
    var debugCalm = false

    /// Tools only: the line's length and where it is heading.
    var debugLine: (len: CGFloat, target: CGFloat, style: String, pumping: Bool) {
        (webLen, webLenTarget, webStyle == .swing ? "swing" : "hang", swingPumping)
    }

    /// Tools only: is the pointer where a hanging spider would go to look at it?
    var debugCursorNear: Bool {
        config.followCursor && cursor.y < webAnchor.y - 60 && abs(cursor.x - webAnchor.x) < 120 * config.scale && t - lastUserActivity < 6
    }

    var debugState: String {
        let m: String
        switch mode {
        case .attached: m = "attached"
        case .airborne: m = air == .jump ? "jump" : (air == .thrown ? "thrown" : "fall")
        case .dangling: m = webStyle == .swing ? "swinging" : "dangling"
        case .held:     m = "held"
        case .nesting:  m = nestPhase == .building ? "building" : "nesting"
        }
        return mode == .attached ? "\(m):\(activity) on \(anchor.loopID)" : m
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
            "pushup": .pushup, "legStretch": .legStretch, "spin": .spin, "eat": .eat,
        ]
        if name == "turn" {
            turnTo(-walkDir, then: .look, for: 1)
            return
        }
        if name == "swing" {
            if mode == .dangling { workUpSwing() } else { _ = startSwing() }
            return
        }
        if name == "build" { buildHammock(); return }
        if name == "nap" { napInHammock(); return }
        guard let a = table[name] else { return }
        beginActivity(a, dur: seconds)
        decisionIn = seconds + 5
    }

    // MARK: - Pose out

    func pose() -> SpiderPose {
        var p = SpiderPose()
        p.pos = pos
        p.heading = heading
        p.spin = rollSpin
        p.facing = clamp(yaw, -1, 1)
        p.grounded = clamp(grounded.value, 0, 1)
        p.scale = config.scale
        // Crouching squashes the whole sprite down onto its feet.
        let squash = 1 - clamp(crouch.value, 0, 1) * 0.26
        p.stretch = clamp(stretch.value * (1 + (1 - squash) * 0.5), 0.74, 1.22)
        p.fatten = clamp(fatten.value * squash, 0.66, 1.26)
        let mirror: CGFloat = yaw >= 0 ? 1 : -1
        var attach = silkAttachLocal()
        attach.x *= mirror
        p.silkAttach = pos + attach.rotated(by: heading) * config.scale
        p.time = t
        p.look = lookSpring.value
        p.blink = clamp(max(blinkValue, sleepiness.value, lid.value), 0, 1)
        p.happy = clamp(happy.value + pettingScore * 0.5 + fed * 0.3, 0, 1)
        if activity == .eat, mode == .attached { p.chew = 0.5 + 0.5 * sin(t * 11) }
        p.startled = clamp(startled.value, 0, 1)
        p.sleep = clamp(sleepiness.value, 0, 1)
        p.abdomenSway = swayWobble.value(t * 1.4) * 0.14
            + sin(gaitPhase * .pi * 2) * 0.09 * min(speed / 60, 1)
            + sin(wagPhase) * wag.value * 0.55
        p.emote = emote
        p.emoteT = emoteDur > 0 ? clamp(emoteTime / emoteDur, 0, 1) : 0
        p.grabbed = grabbed.value
        p.outfit = look
        p.name = name
        p.nameTag = clamp(nameTag.value, 0, 1)
        p.odometer = odometer
        let profile = SpiderRenderer.profileAmount(yaw: yaw)
        // The lean: body and hips turn about a point between the hips and
        // shift a little with it; a foot on the ground stays put, a foot in
        // the air goes with the body.
        let bp = clamp(pitch.value + runNose, -0.6, 0.6)
        p.bodyPitch = bp
        p.bodyShift = V2(-bp * 8, bp * 2)
        let pivot = SpiderRenderer.leanPivot
        func leaned(_ v: V2) -> V2 { pivot + (v - pivot).rotated(by: bp) + p.bodyShift }
        p.legs = legs.enumerated().map { i, leg in
            var hip = SpiderRenderer.rig(i, profile: profile, look: look).hip
            var foot = leg.foot
            if abs(bp) > 0.0005 {
                hip = leaned(hip)
                let inAir = clamp((foot.y - (SpiderRenderer.ground + 3)) / 10, 0, 1)
                if inAir > 0 { foot = V2.lerp(foot, leaned(foot), inAir) }
            }
            let knee: V2
            if let bend = legBend[i] {
                knee = SpiderRenderer.kneeIK(leg: i, hip: hip, foot: foot, away: bend, profile: profile, look: look)
            } else {
                knee = SpiderRenderer.knee(leg: i, hip: hip, foot: foot, lift: leg.lift, profile: profile, look: look)
            }
            return LegPose(hip: hip, knee: knee, foot: foot, lift: leg.lift)
        }
        if webAlpha.value > 0.01 {
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
        if dragAlpha > 0.01 {
            p.dragline = (dragFrom, dragAlpha)
        }
        return p
    }
}
