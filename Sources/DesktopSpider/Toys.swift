import AppKit

// MARK: - Toys
//
// Things put out on the desktop to play with: a ball, a feather on a
// string, a jingle bell, a wind-up bug. They are all one kind of object — a
// small round body with simple physics that falls, bounces off and lands on
// the very surfaces the spider walks, and rolls or slides along them — and
// a kind of toy is only a set of numbers and a few yes-or-nos on it: how
// heavy and how bouncy it is, how far it rolls, whether it drifts down like
// a feather, jingles when knocked, dangles from a string while you carry
// it, or walks off on its own once wound. Nothing in here knows about any
// one toy except how to draw it.
//
// You can pick them up, carry them about and throw them the way you can
// the prey; a click without a drag gives one a poke. The spider's side of
// it — spotting them, sizing them up, and playing — is in Spider.swift.

enum ToyKind: Int, CaseIterable {
    case ball, feather, bell, windUpBug

    var label: String {
        switch self {
        case .ball: return "Ball"
        case .feather: return "Feather"
        case .bell: return "Bell"
        case .windUpBug: return "Wind-up Bug"
        }
    }
    /// Radius of the body, in world px at scale 1.
    var radius: CGFloat {
        switch self {
        case .ball: return 7
        case .feather: return 9
        case .bell: return 6.5
        case .windUpBug: return 7.5
        }
    }
    /// How much of its speed into a surface it keeps coming off it.
    var restitution: CGFloat {
        switch self {
        case .ball: return 0.72
        case .feather: return 0.05
        case .bell: return 0.42
        case .windUpBug: return 0.22
        }
    }
    /// How hard it is to push about, next to the ball.
    var mass: CGFloat {
        switch self {
        case .ball: return 1
        case .feather: return 0.35
        case .bell: return 1.7
        case .windUpBug: return 1.3
        }
    }
    /// Rolls along an edge, turning as it goes, rather than sliding to a stop.
    var rolls: Bool { self == .ball || self == .bell }
    /// How quickly it slows along an edge: a steady drag (per second) and a
    /// constant braking (px/s², at scale 1).
    var edgeDrag: (drag: CGFloat, brake: CGFloat) {
        switch self {
        case .ball: return (0.6, 30)
        case .feather: return (6, 220)
        case .bell: return (0.9, 40)
        case .windUpBug: return (4, 160)
        }
    }
    /// Its share of full gravity: a feather hardly falls at all.
    var gravity: CGFloat { self == .feather ? 0.09 : 1 }
    /// Air resistance, per second.
    var airDrag: CGFloat { self == .feather ? 2.6 : 0.12 }
    /// Drifts from side to side as it comes down, tipping as it goes.
    var flutters: Bool { self == .feather }
    /// How loudly it jingles when knocked about (0: not at all).
    var chime: CGFloat { self == .bell ? 1 : 0 }
    /// Carried dangling on a string this long (px at scale 1), like a wand
    /// toy; 0 for what is carried in the hand, right at the pointer.
    var tether: CGFloat { self == .feather ? 105 : 0 }
    /// Has a key in its back: wound, it walks off by itself until it runs down.
    var windsUp: Bool { self == .windUpBug }
    /// How much a spider's eye is drawn to it sitting still, next to a ball.
    /// (Anything on the move draws it far more.)
    var lure: CGFloat {
        switch self {
        case .ball: return 1
        case .feather: return 1.15
        case .bell: return 0.9
        case .windUpBug: return 1.1
        }
    }
    /// How to throw it up for a pat: the angle off the surface a spider's
    /// bat sends it at, as a range (0 is flat along it).
    var batLoft: ClosedRange<CGFloat> {
        switch self {
        case .ball: return 0.15...0.7
        case .feather: return 0.9...1.3
        case .bell: return 0.05...0.35
        case .windUpBug: return 0...0.15
        }
    }
    var symbol: String {
        switch self {
        case .ball: return "tennisball"
        case .feather: return "leaf"
        case .bell: return "bell"
        case .windUpBug: return "key"
        }
    }
    /// What its memory calls this kind of toy.
    var memoryName: String { "toy.\(self)" }
}

final class Toy {
    let kind: ToyKind
    let id: Int
    var scale: CGFloat
    var pos: V2
    var vel: V2 = .zero
    /// On an edge: which, and where along it. The edge is always one it
    /// sits on top of; anything else it only bounces off.
    private(set) var anchor: Anchor?
    /// Speed along its edge while on one (+ toward the segment's end).
    private(set) var roll: CGFloat = 0
    /// How far round it has turned, for drawing.
    private(set) var spin: CGFloat = 0
    private var spinVel: CGFloat = 0
    /// A tilt that swings and settles: the feather tipping as it drifts,
    /// the bug's wobble.
    private(set) var sway: CGFloat = 0
    private var swayVel: CGFloat = 0
    private(set) var phase: CGFloat = randRange(0, 10)
    private(set) var age: CGFloat = 0
    /// Jingling, 0…1, dying away.
    private(set) var ring: CGFloat = 0
    /// Every knock loud enough to be heard counts one: a spider that
    /// remembers the count knows when there has been a new one.
    private(set) var knocks = 0
    private(set) var lastKnock: CGFloat = 0
    /// How much winding it has left, 0…1: it walks while there is any.
    private(set) var wound: CGFloat = 0
    private(set) var walkDir: CGFloat = 1
    /// Pinned down under a spider: it cannot go anywhere for a moment.
    private(set) var pinnedFor: CGFloat = 0
    /// On the pointer, and where the pointer has hold of it — for a toy on
    /// a string, the top of the string.
    private(set) var held = false
    private(set) var grip = V2.zero
    /// How much string is out, easing to the full length after a pick-up.
    private(set) var string: CGFloat = 0
    /// Moved (or made a sound) this frame.
    private(set) var astir = true
    /// Arriving: fading in as it drops into place.
    private(set) var alpha: CGFloat = 0
    /// Its age when you last had hold of it, threw it or poked it.
    private var handledAge: CGFloat = -99

    init(kind: ToyKind, id: Int, at p: V2, scale: CGFloat) {
        self.kind = kind
        self.id = id
        self.pos = p
        self.scale = scale
        walkDir = chance(0.5) ? 1 : -1
        spin = randRange(-.pi, .pi)
    }

    var radius: CGFloat { kind.radius * scale }
    var onSurface: Bool { anchor != nil }
    var airborne: Bool { anchor == nil && !held }
    /// How fast it is going, whatever it is doing.
    var speed: CGFloat { held ? 0 : (anchor != nil ? abs(roll) : vel.length) }
    /// Hanging from the pointer on its string.
    var dangling: Bool { held && kind.tether > 0 }
    var walking: Bool { wound > 0 && anchor != nil && pinnedFor <= 0 }
    /// You are playing with it with the pointer: holding it, or only just
    /// thrown, dropped, poked or wound it.
    var inPlay: Bool { held || age - handledAge < 4 }
    private static let gravity: CGFloat = 1700

    // MARK: Being played with

    /// A knock: from a spider's front legs, a pounce, a body walking into it.
    /// On an edge, the part along it sets it rolling (or sliding) and enough
    /// of a push off the surface throws it up; in the air it just adds on.
    func bat(_ impulse: V2, map: SurfaceMap) {
        guard !held || kind.tether > 0 else { return }
        let dv = impulse / kind.mass
        if let a = anchor, let seg = map.seg(a) {
            let up = dv.dot(seg.normal)
            let along = dv.dot(seg.dir)
            if up > 70 * scale.squareRoot() {
                anchor = nil
                vel = seg.dir * (roll + along) + seg.normal * up
                spinVel = -(roll + along) / max(radius, 1)
            } else {
                roll += along
            }
        } else {
            vel += dv
        }
        pinnedFor = 0
        // A knock turns the key a little.
        if kind.windsUp { wound = min(1, wound + 0.3) }
        swayVel += (impulse.x >= 0 ? -1 : 1) * min(impulse.length, 400) * 0.02
        jingle(impulse.length / 380)
    }

    /// A click on it (not a drag): each kind has its own answer to that.
    func poke(map: SurfaceMap) {
        guard !held else { return }
        handledAge = age
        let hop = V2(randRange(-60, 60), 0)
        switch kind {
        case .ball:
            bat(V2(0, 330) + hop, map: map)
        case .bell:
            jingle(1)
            bat(V2(0, 160) + hop * 0.5, map: map)
        case .feather:
            // Puffed up into the air, to drift down again.
            bat(V2(randRange(-30, 30), 190), map: map)
        case .windUpBug:
            // Wound right up.
            wound = 1
            swayVel += 3
            phase = 0
        }
    }

    /// Run into something standing still (a spider's legs): it comes off it,
    /// having lost most of its speed. `n` is the way out, away from it.
    func bump(_ n: V2, map: SurfaceMap) {
        guard !held else { return }
        if let a = anchor, let seg = map.seg(a) {
            let away: CGFloat = n.dot(seg.dir) >= 0 ? 1 : -1
            guard roll * away < 0 else { return }
            jingle(abs(roll) / 400)
            roll = -roll * 0.3
            if walking { walkDir = away; roll = 0 }
        } else {
            let vn = vel.dot(n)
            guard vn < 0 else { return }
            vel -= n * vn * 1.35
            jingle(-vn / 400)
        }
    }

    /// Pounced on and held down under a spider for a moment.
    func pin(for secs: CGFloat) {
        pinnedFor = max(pinnedFor, secs)
        roll = 0
        if anchor == nil { vel *= 0.3 }
        jingle(0.6)
    }

    /// Nudged along by something walking into it, at `push` px/s along its
    /// edge (or through the air): it goes at least that fast, that way.
    func shove(_ push: V2, map: SurfaceMap) {
        guard !held, pinnedFor <= 0 else { return }
        if let a = anchor, let seg = map.seg(a) {
            let along = push.dot(seg.dir) / kind.mass.squareRoot()
            if along > 0 ? roll < along : roll > along {
                if abs(along - roll) > 90 { jingle(abs(along - roll) / 500) }
                roll = along
            }
        } else if vel.dot(push.normalized) < push.length {
            vel += push.normalized * (push.length - max(vel.dot(push.normalized), 0)) / kind.mass.squareRoot()
        }
    }

    /// On a line from something hauling it off (a spider towing it): never
    /// further than `length` from `p`. On an edge it is dragged along after
    /// it — rolling, or skidding — and a line going up steeply lifts it off;
    /// in the air it swings on the line. How far past its length the line
    /// was stretched, which is how hard it pulled.
    @discardableResult
    func haul(from p: V2, length: CGFloat, map: SurfaceMap) -> CGFloat {
        guard !held else { return 0 }
        let d = pos - p
        let dist = d.length
        guard dist > length, dist > 0.001 else { return 0 }
        let excess = dist - length
        let pull = -d / dist
        pinnedFor = 0
        if let a = anchor, let seg = map.seg(a) {
            if pull.dot(seg.normal) > 0.8, excess > 4 * scale {
                anchor = nil
                vel = pull * min(excess * 12, 260)
                return excess
            }
            // Taken up over about a tenth of a second, the heavier the slower.
            let want = clamp(pull.dot(seg.dir) * excess * 10 / kind.mass.squareRoot(), -420, 420)
            if want > 0 ? roll < want : roll > want {
                if abs(want - roll) > 120 { jingle(abs(want - roll) / 600) }
                roll = want
                if walking { walkDir = want >= 0 ? 1 : -1 }
            }
        } else {
            let n = d / dist
            pos = p + n * length
            let out = vel.dot(n)
            if out > 0 { vel -= n * out }
        }
        return excess
    }

    private func jingle(_ amount: CGFloat) {
        guard kind.chime > 0, amount > 0.05 else { return }
        let a = min(1, amount * kind.chime)
        if a > 0.15, a > ring * 0.8 {
            knocks += 1
            lastKnock = a
        }
        ring = max(ring, a)
    }

    // MARK: Carried

    func grab(at p: V2) {
        held = true
        handledAge = age
        anchor = nil
        roll = 0
        pinnedFor = 0
        grip = p
        if kind.tether > 0 {
            // Taken up on its string: from where it lies if that is in
            // reach, else it comes to hang just under the pointer.
            if pos.distance(to: p) > kind.tether * scale { pos = p - V2(0, 12 * scale); vel = .zero }
            string = pos.distance(to: p)
        } else {
            string = 0
            pos = p
            vel = .zero
        }
    }

    func drag(to p: V2) {
        guard held else { return }
        grip = p
        handledAge = age
    }

    /// Wound right up, ready to go the moment it is set down.
    func wind() {
        guard kind.windsUp else { return }
        wound = 1
        swayVel += 3
        handledAge = age
    }

    /// Let go. Something carried in the hand flies off with the pointer's
    /// fling; something on a string swings free with its own.
    func release(fling: V2) {
        guard held else { return }
        held = false
        handledAge = age
        if kind.tether <= 0 { vel = fling.clampedLength(1400) }
        spinVel = -vel.x / max(radius, 1) * 0.5
    }

    // MARK: Physics

    func update(dt: CGFloat, map: SurfaceMap) {
        age += dt
        phase += dt
        let before = pos
        let ringBefore = ring
        alpha = min(1, alpha + dt / 0.35)
        ring *= exp(-2.4 * dt)
        if ring < 0.01 { ring = 0 }
        pinnedFor = max(0, pinnedFor - dt)
        // The spring of the tilt.
        swayVel += (-sway * 40 - swayVel * 5) * dt
        sway += swayVel * dt
        if wound > 0 {
            // A wind lasts a quarter of a minute or so; held down, it
            // churns through it faster.
            wound = max(0, wound - dt / (pinnedFor > 0 ? 6 : 16))
        }

        if held {
            updateHeld(dt: dt)
        } else if anchor != nil {
            updateOnEdge(dt: dt, map: map)
        } else {
            updateInAir(dt: dt, map: map)
        }
        stayInTheWorld(map: map, dt: dt)
        astir = pos.distance(to: before) > 0.05 || ring > 0.02 || ringBefore > 0.02 || alpha < 1 || walking || abs(swayVel) > 0.05
    }

    private func updateHeld(dt: CGFloat) {
        guard kind.tether > 0 else {
            // In the hand: shaken, a bell jingles.
            let moved = dt > 0 ? grip.distance(to: pos) / dt : 0
            if moved > 350 { jingle(moved / 1800) }
            pos = grip
            sway = sin(phase * 7) * 0.12
            return
        }
        // On its string: pulled after the pointer, swinging below it.
        string = approach(string, kind.tether * scale, 3.5, dt)
        vel.y -= Toy.gravity * 0.5 * dt
        vel *= exp(-1.6 * dt)
        pos += vel * dt
        let d = pos - grip
        if d.length > string {
            let n = d.normalized
            pos = grip + n * string
            let out = vel.dot(n)
            if out > 0 { vel -= n * out }
        }
        // The feather trails behind as it swings.
        swayVel += clamp(-vel.x * 0.004, -0.6, 0.6)
        spin = approach(spin, clamp(vel.x / 500, -0.8, 0.8), 6, dt)
    }

    private func updateOnEdge(dt: CGFloat, map: SurfaceMap) {
        guard let a = anchor, let loop = map.loop(a.loopID), a.segIdx < loop.segs.count else {
            // Its surface has gone (the window closed): it falls.
            anchor = nil
            vel = .zero
            return
        }
        let seg = loop.segs[a.segIdx]
        if pinnedFor > 0 {
            roll = 0
        } else if walking {
            // Clockwork: it gets up to its pace and trundles along, turning
            // round at walls.
            let pace = 34 * scale * min(1, 0.35 + wound * 2)
            roll = approach(roll, walkDir * pace, 5, dt)
            swayVel += sin(phase * 22) * 0.4
        } else {
            let (drag, brake) = kind.edgeDrag
            roll *= exp(-drag * dt)
            let b = brake * scale * dt
            roll = roll > 0 ? max(0, roll - b) : min(0, roll + b)
            if abs(roll) < 1 { roll = 0 }
        }
        if roll != 0 { advance(roll * dt, on: loop, seg: seg, a: a, map: map) }
        if let b = anchor, let l = map.loop(b.loopID), b.segIdx < l.segs.count {
            tipIfOverhanging(loop: l, seg: l.segs[b.segIdx], a: b, map: map)
        }
        if let b = anchor, let s = map.seg(b) {
            place(s, t: b.t, map: map)
            vel = s.dir * roll
        }
        if kind.rolls {
            spin -= roll * dt / max(radius, 1)
            // A jingle bell rattles as it rolls.
            if kind.chime > 0, abs(roll) > 30 { ring = max(ring, min(0.4, abs(roll) / 500) * kind.chime) }
        } else if kind.flutters {
            spin = approach(spin, 0, 4, dt)
        } else {
            spin = approach(spin, 0, 8, dt)
        }
    }

    /// Along its edge by `d`: onto the next edge round a flat join, back off
    /// a wall it runs into, and off the end of anything with a drop past it.
    private func advance(_ d: CGFloat, on loop: SurfaceLoop, seg: Seg, a: Anchor, map: SurfaceMap) {
        var a = a
        let nt = a.t + d
        guard seg.isOpen(at: clamp(nt, 0, seg.len)) else {
            // Something in front covers that stretch: off it, as off a wall.
            bounceBack()
            return
        }
        let forward = d > 0
        // How far past the end of its line the body's middle has got.
        let past = forward ? nt - seg.len : -nt
        switch corner(loop: loop, segIdx: a.segIdx, forward: forward) {
        case .flat(let ni, let t2):
            if past <= 0 {
                a.t = nt
            } else {
                a.segIdx = ni
                a.t = t2 + (forward ? past : -past)
            }
            anchor = a
        case .wall:
            // The line stops a body's height short of a wall; the toy goes
            // on until it touches it.
            if past <= map.standoff - radius { a.t = nt; anchor = a } else { bounceBack() }
        case .drop:
            // The line runs a body's height past the edge of a drop; the
            // toy tips off once its middle is over the edge.
            if past <= -map.standoff { a.t = nt; anchor = a } else { tipOff(seg: seg, map: map) }
        }
    }

    /// Set down (or landed) out past the edge of what it is on: it tips off.
    private func tipIfOverhanging(loop: SurfaceLoop, seg: Seg, a: Anchor, map: SurfaceMap) {
        for forward in [true, false] {
            let past = forward ? a.t - seg.len : -a.t
            guard past > -map.standoff, case .drop = corner(loop: loop, segIdx: a.segIdx, forward: forward) else { continue }
            if roll == 0 || (roll > 0) == forward { roll = (forward ? 1 : -1) * max(abs(roll), 25 * scale) }
            tipOff(seg: seg, map: map)
            return
        }
    }

    private enum Corner { case flat(Int, CGFloat), wall, drop }

    /// What is past one end of an edge: more to sit on, a wall going up, or
    /// a drop.
    private func corner(loop: SurfaceLoop, segIdx: Int, forward: Bool) -> Corner {
        let seg = loop.segs[segIdx]
        var ni = segIdx + (forward ? 1 : -1)
        if loop.closed { ni = (ni + loop.segs.count) % loop.segs.count }
        guard loop.segs.indices.contains(ni), ni != segIdx else { return .drop }
        let next = loop.segs[ni]
        let joined = forward ? next.a.distance(to: seg.b) < 2 : next.b.distance(to: seg.a) < 2
        guard joined else { return .drop }
        if next.facing == .up { return .flat(ni, forward ? 0 : next.len) }
        // The way the next edge leads on from the join.
        let on = forward ? next.dir : -next.dir
        return on.dot(seg.normal) > 0.5 ? .wall : .drop
    }

    /// Whether the top of an edge is under `u`: not out past the end of it
    /// where it drops away.
    private func supports(loop: SurfaceLoop, segIdx: Int, at u: CGFloat, map: SurfaceMap) -> Bool {
        let seg = loop.segs[segIdx]
        if u < map.standoff + 1, case .drop = corner(loop: loop, segIdx: segIdx, forward: false) { return false }
        if u > seg.len - map.standoff - 1, case .drop = corner(loop: loop, segIdx: segIdx, forward: true) { return false }
        return true
    }

    private func bounceBack() {
        roll = -roll * max(kind.restitution, 0.3)
        if walking { walkDir = roll >= 0 ? 1 : -1; roll = walkDir * abs(roll) }
        swayVel += roll >= 0 ? -1.5 : 1.5
        jingle(abs(roll) / 300)
    }

    private func tipOff(seg: Seg, map: SurfaceMap) {
        anchor = nil
        // Over the edge and going: never teetering on it.
        let way: CGFloat = roll >= 0 ? 1 : -1
        let along = way * max(abs(roll), 30 * scale)
        pos += seg.dir * way * 1.5
        vel = seg.dir * along + seg.normal * 10
        spinVel = -along / max(radius, 1)
    }

    private func place(_ seg: Seg, t: CGFloat, map: SurfaceMap) {
        // Its middle sits its own radius off the edge; the edge's line is
        // stood off it by the spider's body height.
        pos = seg.a + seg.dir * t - seg.normal * (map.standoff - radius)
    }

    private func updateInAir(dt: CGFloat, map: SurfaceMap) {
        vel.y -= Toy.gravity * kind.gravity * dt
        if kind.flutters {
            // Side to side and a little lift on each swing: a falling leaf.
            let swing = sin(phase * 2.4)
            vel.x += swing * 150 * dt
            vel.y += abs(swing) * 40 * dt
            spin = approach(spin, swing * 0.7, 3, dt)
        } else {
            spin += spinVel * dt
            spinVel *= exp(-0.4 * dt)
        }
        vel *= exp(-kind.airDrag * dt)
        // In short steps, so nothing quick goes through a thin edge.
        let travel = vel.length * dt
        let steps = max(1, min(8, Int(ceil(travel / max(radius * 0.8, 2)))))
        let h = dt / CGFloat(steps)
        for _ in 0..<steps {
            let from = pos
            pos += vel * h
            if collide(from: from, map: map) { break }
        }
    }

    /// Whether the move from `from` to `pos` went through a surface: if so,
    /// it comes off it — or, slow enough and on top of it, comes to rest.
    private func collide(from: V2, map: SurfaceMap) -> Bool {
        let off = map.standoff - radius
        var best: (f: CGFloat, loop: SurfaceLoop, idx: Int, u: CGFloat)?
        let move = pos - from
        for loop in map.loops {
            for (i, s) in loop.segs.enumerated() {
                let n = s.normal
                guard move.dot(n) < 0 else { continue }
                let p0 = s.a - n * off
                let d0 = (from - p0).dot(n)
                let d1 = (pos - p0).dot(n)
                guard d0 >= -0.5, d1 < 0 else { continue }
                let f = d0 / max(d0 - d1, 0.0001)
                let hit = from + move * f
                let u = (hit - p0).dot(s.dir)
                // A little way past each end counts, so a corner is not a gap.
                guard u > -radius * 0.6, u < s.len + radius * 0.6, s.isOpen(at: clamp(u, 0, s.len)) else { continue }
                // The top of something only holds it up as far as its edges:
                // past one with a drop beyond, it goes on by.
                if s.facing == .up, !supports(loop: loop, segIdx: i, at: u, map: map) { continue }
                if best == nil || f < best!.f { best = (f, loop, i, u) }
            }
        }
        guard let b = best else { return false }
        let s = b.loop.segs[b.idx]
        let n = s.normal
        let vn = vel.dot(n)
        let vt = vel - n * vn
        pos = from + move * b.f + n * 0.3
        let impact = -vn
        if s.facing == .up, impact < 120 * max(scale, 0.6) + (kind.flutters ? 400 : 0) {
            // Down, and staying down.
            anchor = Anchor(loopID: b.loop.id, segIdx: b.idx, t: clamp(b.u, 0, s.len))
            roll = vt.dot(s.dir) * (kind.rolls ? 0.95 : 0.5)
            vel = .zero
            place(s, t: anchor!.t, map: map)
            jingle(impact / 600)
            if impact > 40 { swayVel += 2 }
            return true
        }
        let e = kind.restitution
        vel = vt * (kind.rolls ? 0.92 : 0.7) - n * vn * e
        spinVel = -vt.dot(V2(-n.y, n.x)) / max(radius, 1)
        swayVel += 3 * (vt.x >= 0 ? -1 : 1)
        jingle(impact / 500)
        return true
    }

    /// The rim of the screen is always there, whatever the surfaces say (a
    /// box drawn somewhere takes the rest of them away): it never goes off
    /// the edge of the world, and never falls through the bottom of it.
    private func stayInTheWorld(map: SurfaceMap, dt: CGFloat) {
        guard !held else { return }
        let f = map.screenFrame(containing: pos)
        let r = radius
        if pos.x < f.minX + r { pos.x = f.minX + r; if vel.x < 0 { vel.x = -vel.x * kind.restitution }; if roll < 0 { roll = -roll * 0.3 } }
        if pos.x > f.maxX - r { pos.x = f.maxX - r; if vel.x > 0 { vel.x = -vel.x * kind.restitution }; if roll > 0 { roll = -roll * 0.3 } }
        if pos.y > f.maxY - r { pos.y = f.maxY - r; if vel.y > 0 { vel.y = -vel.y * kind.restitution } }
        if anchor == nil, pos.y < f.minY + r {
            pos.y = f.minY + r
            if vel.y < 0 { vel.y = -vel.y * kind.restitution }
            if vel.y < 60 { vel.y = 0 }
            vel.x *= exp(-3 * dt)
        }
    }

    /// Bounding box for redraws, in world px: with room for the jingle, and
    /// the string up to the pointer.
    var bounds: CGRect {
        let r = radius * 2.6 + 6
        var b = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
        if dangling { b = b.union(CGRect(x: grip.x - 4, y: grip.y - 4, width: 8, height: 8)) }
        return b
    }
}

// MARK: - The toy box

/// All the toys out on the desktop. Every spider there — yours, and any
/// visitors — can play with them.
final class ToyBox {
    let map: SurfaceMap
    private(set) var toys: [Toy] = []
    private var nextID = 1
    static let most = 4
    var scale: CGFloat = 1 {
        didSet { for t in toys { t.scale = scale } }
    }
    /// A toy made a noise: for the bell's jingle.
    var onJingle: ((Toy, CGFloat) -> Void)?
    private var heard: [Int: Int] = [:]

    init(map: SurfaceMap) {
        self.map = map
    }

    var canAdd: Bool { toys.count < ToyBox.most }
    var isEmpty: Bool { toys.isEmpty }
    /// Anything moving, or ringing, this frame.
    var astir: Bool { toys.contains { $0.astir } }

    /// Puts one out: dropped in from a little way up onto something to sit
    /// on some way off from `near` (in `area`, if given), so you see it
    /// arrive — a feather from higher up, to drift down.
    @discardableResult
    func add(_ kind: ToyKind, near p: V2, in area: CGRect? = nil) -> Toy? {
        guard canAdd else { return nil }
        let screen = area ?? map.screenFrame(containing: p)
        var best: (score: CGFloat, point: V2)?
        for spot in map.sampleSpots(spacing: 40) where spot.seg.facing == .up && screen.contains(spot.point.point) {
            let d = spot.point.distance(to: p)
            guard d > 120 * scale, spot.seg.isOpen(at: spot.anchor.t) else { continue }
            // Not right on top of another toy.
            guard !toys.contains(where: { $0.pos.distance(to: spot.point) < 60 * scale }) else { continue }
            let score = remap(d, 120, 600, 1.2, 0.5) * spot.loop.kind.appeal * randRange(0.6, 1.4)
            if best == nil || score > best!.score { best = (score, spot.point) }
        }
        var at = best?.point ?? V2(clamp(p.x + randRange(-250, 250), screen.minX + 60, screen.maxX - 60), screen.minY + 40)
        let drop: CGFloat = kind == .feather ? 220 : (kind == .ball ? 140 : 60)
        at.y = min(at.y + drop * scale, screen.maxY - 40)
        let toy = Toy(kind: kind, id: nextID, at: at, scale: scale)
        nextID += 1
        toys.append(toy)
        return toy
    }

    /// Puts one in your hand at `p`, putting away whatever else is out.
    @discardableResult
    func place(_ kind: ToyKind, at p: V2) -> Toy {
        removeAll()
        let toy = Toy(kind: kind, id: nextID, at: p, scale: scale)
        nextID += 1
        toys.append(toy)
        return toy
    }

    /// Tools only: puts a toy made elsewhere into the box.
    func debugInsert(_ toy: Toy) { toys.append(toy) }

    func remove(_ toy: Toy) {
        toys.removeAll { $0 === toy }
        heard[toy.id] = nil
    }

    func removeAll() {
        toys = []
        heard = [:]
    }

    func toy(_ id: Int) -> Toy? { toys.first { $0.id == id } }

    func update(dt: CGFloat) {
        for toy in toys {
            toy.update(dt: dt, map: map)
            if toy.knocks != heard[toy.id] ?? 0 {
                heard[toy.id] = toy.knocks
                onJingle?(toy, toy.lastKnock)
            }
        }
    }

    /// The toy under the pointer, if any, to pick up: the nearest,
    /// generously — never the one already on the pointer.
    func hit(_ p: V2) -> Toy? {
        toys.filter { !$0.held && $0.pos.distance(to: p) < $0.radius + 10 }.min { $0.pos.distance(to: p) < $1.pos.distance(to: p) }
    }
}

// MARK: - Drawing

enum ToyRenderer {
    private static let outline = CGColor(red: 0.18, green: 0.13, blue: 0.1, alpha: 1)

    /// Draws a toy in world coordinates less `origin`, y up: its shadow, its
    /// string, the jingle, and the toy itself.
    static func draw(_ toy: Toy, in ctx: CGContext, origin: CGPoint) {
        let p = CGPoint(x: toy.pos.x - origin.x, y: toy.pos.y - origin.y)
        let s = toy.scale
        ctx.saveGState()
        ctx.setAlpha(toy.alpha)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if toy.dangling {
            // The string, sagging a little when it is slack.
            let g = CGPoint(x: toy.grip.x - origin.x, y: toy.grip.y - origin.y)
            let tie = CGPoint(x: p.x + sin(toy.sway) * 8 * s, y: p.y + cos(toy.sway) * 8 * s)
            let slack = max(0, toy.string - toy.pos.distance(to: toy.grip))
            ctx.setStrokeColor(CGColor(red: 0.35, green: 0.3, blue: 0.28, alpha: 0.85))
            ctx.setLineWidth(1)
            ctx.beginPath()
            ctx.move(to: g)
            ctx.addQuadCurve(to: tie, control: CGPoint(x: (g.x + tie.x) / 2, y: (g.y + tie.y) / 2 - slack * 0.6))
            ctx.strokePath()
        }
        if toy.onSurface {
            // A soft contact shadow.
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.13))
            let w = toy.radius * 2.1
            ctx.fillEllipse(in: CGRect(x: p.x - w / 2, y: p.y - toy.radius - 1.6 * s, width: w, height: 3.4 * s))
        }
        if toy.ring > 0.02 {
            // Jingling: little arcs either side, spreading as they fade.
            let r = toy.radius
            for side in [CGFloat(-1), 1] {
                for k in 0..<2 {
                    let spread = r * (1.5 + CGFloat(k) * 0.55) + (1 - toy.ring) * r * 0.6
                    let a0: CGFloat = side > 0 ? -0.55 : .pi - 0.55
                    ctx.setStrokeColor(CGColor(red: 0.85, green: 0.65, blue: 0.2, alpha: toy.ring * (k == 0 ? 0.9 : 0.55)))
                    ctx.setLineWidth(1.3 * s)
                    ctx.beginPath()
                    ctx.addArc(center: CGPoint(x: p.x, y: p.y + r * 0.4), radius: spread,
                               startAngle: a0, endAngle: a0 + 1.1, clockwise: false)
                    ctx.strokePath()
                }
            }
        }
        ctx.translateBy(x: p.x, y: p.y)
        ctx.scaleBy(x: s, y: s)
        switch toy.kind {
        case .ball: drawBall(toy, in: ctx)
        case .feather: drawFeather(toy, in: ctx)
        case .bell: drawBell(toy, in: ctx)
        case .windUpBug: drawBug(toy, in: ctx)
        }
        ctx.restoreGState()
    }

    /// A little bouncy ball: red, with a white band that turns as it rolls.
    private static func drawBall(_ toy: Toy, in ctx: CGContext) {
        let r = toy.kind.radius
        let body = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        ctx.setFillColor(CGColor(red: 0.88, green: 0.24, blue: 0.22, alpha: 1))
        ctx.fillEllipse(in: body)
        ctx.saveGState()
        ctx.addEllipse(in: body)
        ctx.clip()
        ctx.rotate(by: toy.spin)
        ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.88, alpha: 1))
        ctx.fill(CGRect(x: -r, y: -r * 0.28, width: r * 2, height: r * 0.56))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: r * 0.35, y: -r * 0.2, width: r * 0.4, height: r * 0.4))
        ctx.restoreGState()
        // Lit from above, whichever way it has turned.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
        ctx.fillEllipse(in: CGRect(x: -r * 0.55, y: r * 0.2, width: r * 0.55, height: r * 0.4))
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.9)
        ctx.strokeEllipse(in: body)
    }

    /// A round jingle bell: brass, a slot across the bottom, a loop on top.
    private static func drawBell(_ toy: Toy, in ctx: CGContext) {
        let r = toy.kind.radius
        let body = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.rotate(by: toy.spin + toy.sway * 0.3)
        // The loop it hangs from.
        ctx.setStrokeColor(CGColor(red: 0.6, green: 0.45, blue: 0.12, alpha: 1))
        ctx.setLineWidth(1.4)
        ctx.strokeEllipse(in: CGRect(x: -1.8, y: r - 1, width: 3.6, height: 3.6))
        let brass = [CGColor(red: 1, green: 0.88, blue: 0.45, alpha: 1), CGColor(red: 0.8, green: 0.58, blue: 0.16, alpha: 1)]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: brass as CFArray, locations: [0, 1]) {
            ctx.saveGState()
            ctx.addEllipse(in: body)
            ctx.clip()
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: -r * 0.35, y: r * 0.35), startRadius: 0,
                                   endCenter: .zero, endRadius: r * 1.2, options: [])
            ctx.restoreGState()
        }
        // The slot, and the holes at its ends.
        ctx.setStrokeColor(CGColor(red: 0.3, green: 0.2, blue: 0.06, alpha: 1))
        ctx.setLineWidth(1.3)
        ctx.beginPath(); ctx.move(to: CGPoint(x: -r * 0.55, y: -r * 0.3)); ctx.addLine(to: CGPoint(x: r * 0.55, y: -r * 0.3)); ctx.strokePath()
        ctx.setFillColor(CGColor(red: 0.3, green: 0.2, blue: 0.06, alpha: 1))
        for x in [-r * 0.55, r * 0.55] { ctx.fillEllipse(in: CGRect(x: x - 1.1, y: -r * 0.3 - 1.1, width: 2.2, height: 2.2)) }
        // A band round its middle.
        ctx.setStrokeColor(CGColor(red: 0.62, green: 0.44, blue: 0.1, alpha: 0.8))
        ctx.setLineWidth(0.8)
        ctx.beginPath(); ctx.move(to: CGPoint(x: -r, y: r * 0.12)); ctx.addQuadCurve(to: CGPoint(x: r, y: r * 0.12), control: CGPoint(x: 0, y: -r * 0.1)); ctx.strokePath()
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.8)
        ctx.strokeEllipse(in: body)
        ctx.restoreGState()
        // A glint.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.95, alpha: 0.7))
        ctx.fillEllipse(in: CGRect(x: -r * 0.5, y: r * 0.25, width: r * 0.4, height: r * 0.3))
    }

    /// A fluffy feather, curved, on its quill: lying flat when down,
    /// tipping as it drifts, trailing from its string.
    private static func drawFeather(_ toy: Toy, in ctx: CGContext) {
        ctx.rotate(by: toy.onSurface ? 0.05 : toy.spin + toy.sway * 0.4)
        let vane = CGColor(red: 0.42, green: 0.72, blue: 0.9, alpha: 1)
        let tip = CGColor(red: 0.95, green: 0.55, blue: 0.75, alpha: 1)
        // The vane: a soft teardrop along a curved quill, from the tied end
        // at the left to the tip.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -11, y: 0))
        path.addCurve(to: CGPoint(x: 12, y: 1.5), control1: CGPoint(x: -6, y: 7), control2: CGPoint(x: 7, y: 7.5))
        path.addCurve(to: CGPoint(x: -11, y: 0), control1: CGPoint(x: 7, y: -3.5), control2: CGPoint(x: -5, y: -4))
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let cols = [vane, tip]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols as CFArray, locations: [0.35, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: -11, y: 0), end: CGPoint(x: 12, y: 0), options: [])
        }
        // Barbs, ruffling as it moves.
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.4))
        ctx.setLineWidth(0.6)
        let ruffle = sin(toy.phase * 9) * (toy.airborne || toy.dangling ? 0.8 : 0.15)
        for i in 0..<8 {
            let x = -8 + CGFloat(i) * 2.6
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: 0.8)); ctx.addLine(to: CGPoint(x: x + 2.4, y: 6 + ruffle)); ctx.strokePath()
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: 0.4)); ctx.addLine(to: CGPoint(x: x + 2.4, y: -3.5 - ruffle)); ctx.strokePath()
        }
        ctx.restoreGState()
        // The quill.
        ctx.setStrokeColor(CGColor(red: 0.95, green: 0.93, blue: 0.85, alpha: 1))
        ctx.setLineWidth(1)
        ctx.beginPath(); ctx.move(to: CGPoint(x: -13, y: -0.8)); ctx.addQuadCurve(to: CGPoint(x: 11, y: 1.4), control: CGPoint(x: 0, y: 2.6)); ctx.strokePath()
        // Fluff at the base.
        ctx.setFillColor(CGColor(red: 0.85, green: 0.92, blue: 1, alpha: 0.85))
        for (x, y) in [(CGFloat(-10), CGFloat(1.5)), (-9, -1.8), (-11.5, 0.2)] {
            ctx.fillEllipse(in: CGRect(x: x - 1.6, y: y - 1.2, width: 3.2, height: 2.4))
        }
    }

    /// A tin wind-up beetle: a painted dome with a key in its back that
    /// turns while it walks, and little legs that scurry.
    private static func drawBug(_ toy: Toy, in ctx: CGContext) {
        let face: CGFloat = toy.airborne ? (toy.vel.x >= 0 ? 1 : -1) : toy.walkDir
        ctx.rotate(by: toy.sway * 0.06 + (toy.airborne ? toy.spin * 0.3 : 0))
        ctx.scaleBy(x: face, y: 1)
        let r = toy.kind.radius
        let run = toy.walking || toy.airborne
        // Legs: three a side, seen side on, ticking round when it walks.
        ctx.setStrokeColor(CGColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1))
        ctx.setLineWidth(1)
        for i in 0..<3 {
            let x = -r * 0.55 + CGFloat(i) * r * 0.55
            let step = run ? sin(toy.phase * 24 + CGFloat(i) * 2.1) * 1.8 : 0
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: -r * 0.35)); ctx.addLine(to: CGPoint(x: x + step, y: -r - 0.4)); ctx.strokePath()
        }
        // The key, standing up out of its back.
        let turn = toy.wound > 0 ? toy.phase * 5 : 0
        ctx.saveGState()
        ctx.translateBy(x: -r * 0.2, y: r * 0.75)
        ctx.setFillColor(CGColor(red: 0.8, green: 0.62, blue: 0.22, alpha: 1))
        ctx.fill(CGRect(x: -0.6, y: 0, width: 1.2, height: 3))
        let w = 3.2 * abs(cos(turn)) + 0.8
        ctx.fillEllipse(in: CGRect(x: -w - 0.4, y: 2.2, width: w, height: 3))
        ctx.fillEllipse(in: CGRect(x: 0.4, y: 2.2, width: w, height: 3))
        ctx.restoreGState()
        // The tin shell: painted teal, with a seam and rivets.
        let shell = CGMutablePath()
        shell.move(to: CGPoint(x: -r, y: -r * 0.4))
        shell.addQuadCurve(to: CGPoint(x: r * 0.7, y: -r * 0.4), control: CGPoint(x: -r * 0.2, y: r * 1.45))
        shell.closeSubpath()
        ctx.setFillColor(CGColor(red: 0.18, green: 0.62, blue: 0.62, alpha: 1))
        ctx.addPath(shell)
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1))
        ctx.setLineWidth(0.9)
        ctx.beginPath(); ctx.move(to: CGPoint(x: -r * 0.9, y: -r * 0.15)); ctx.addLine(to: CGPoint(x: r * 0.6, y: -r * 0.15)); ctx.strokePath()
        ctx.setFillColor(CGColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1))
        for x in [-r * 0.55, -r * 0.1, r * 0.3] { ctx.fillEllipse(in: CGRect(x: x - 0.6, y: r * 0.2, width: 1.2, height: 1.2)) }
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.8)
        ctx.addPath(shell)
        ctx.strokePath()
        // The head, and two painted eyes.
        ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.24, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: r * 0.55, y: -r * 0.45, width: r * 0.7, height: r * 0.65))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: r * 0.85, y: -r * 0.1, width: 1.8, height: 1.8))
        ctx.setFillColor(outline)
        ctx.fillEllipse(in: CGRect(x: r * 1.0, y: -r * 0.05, width: 0.9, height: 0.9))
    }
}
