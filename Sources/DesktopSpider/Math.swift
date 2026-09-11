import CoreGraphics
import Foundation

// MARK: - 2D vector

struct V2 {
    var x: CGFloat
    var y: CGFloat

    static let zero = V2(0, 0)

    init(_ x: CGFloat, _ y: CGFloat) { self.x = x; self.y = y }
    init(_ p: CGPoint) { self.x = p.x; self.y = p.y }

    var point: CGPoint { CGPoint(x: x, y: y) }
    var length: CGFloat { (x * x + y * y).squareRoot() }
    var lengthSquared: CGFloat { x * x + y * y }
    var angle: CGFloat { atan2(y, x) }

    /// 90 degrees counter clockwise.
    var perp: V2 { V2(-y, x) }

    var normalized: V2 {
        let l = length
        return l > 1e-9 ? V2(x / l, y / l) : V2(1, 0)
    }

    func rotated(by a: CGFloat) -> V2 {
        let c = cos(a), s = sin(a)
        return V2(x * c - y * s, x * s + y * c)
    }

    func dot(_ o: V2) -> CGFloat { x * o.x + y * o.y }
    func cross(_ o: V2) -> CGFloat { x * o.y - y * o.x }
    func distance(to o: V2) -> CGFloat { (self - o).length }

    func clampedLength(_ maxLen: CGFloat) -> V2 {
        let l = length
        return l > maxLen ? self * (maxLen / l) : self
    }

    static func + (a: V2, b: V2) -> V2 { V2(a.x + b.x, a.y + b.y) }
    static func - (a: V2, b: V2) -> V2 { V2(a.x - b.x, a.y - b.y) }
    static func * (a: V2, s: CGFloat) -> V2 { V2(a.x * s, a.y * s) }
    static func * (s: CGFloat, a: V2) -> V2 { V2(a.x * s, a.y * s) }
    static func / (a: V2, s: CGFloat) -> V2 { V2(a.x / s, a.y / s) }
    static func += (a: inout V2, b: V2) { a = a + b }
    static func -= (a: inout V2, b: V2) { a = a - b }
    static func *= (a: inout V2, s: CGFloat) { a = a * s }

    static prefix func - (a: V2) -> V2 { V2(-a.x, -a.y) }

    static func angle(_ a: CGFloat) -> V2 { V2(cos(a), sin(a)) }
    static func lerp(_ a: V2, _ b: V2, _ t: CGFloat) -> V2 { a + (b - a) * t }
}

// MARK: - Scalar helpers

@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

@inline(__always) func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Maps `v` from one range to another, clamped.
@inline(__always) func remap(_ v: CGFloat, _ inLo: CGFloat, _ inHi: CGFloat,
                             _ outLo: CGFloat, _ outHi: CGFloat) -> CGFloat {
    guard abs(inHi - inLo) > 1e-9 else { return outLo }
    return lerp(outLo, outHi, clamp((v - inLo) / (inHi - inLo), 0, 1))
}

/// Frame-rate independent exponential approach. `rate` is roughly "how much per second".
@inline(__always) func approach(_ value: CGFloat, _ target: CGFloat, _ rate: CGFloat, _ dt: CGFloat) -> CGFloat {
    let t = 1 - exp(-rate * dt)
    return value + (target - value) * t
}

@inline(__always) func approach(_ value: V2, _ target: V2, _ rate: CGFloat, _ dt: CGFloat) -> V2 {
    let t = 1 - exp(-rate * dt)
    return value + (target - value) * t
}

/// Shortest signed difference between two angles, in (-pi, pi].
@inline(__always) func angleDelta(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
    var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}

func smoothstep(_ t: CGFloat) -> CGFloat {
    let x = clamp(t, 0, 1)
    return x * x * (3 - 2 * x)
}

func easeOutCubic(_ t: CGFloat) -> CGFloat {
    let x = clamp(t, 0, 1)
    return 1 - pow(1 - x, 3)
}

func easeInOutSine(_ t: CGFloat) -> CGFloat {
    -(cos(.pi * clamp(t, 0, 1)) - 1) / 2
}

/// Overshooting ease, good for pops and hops.
func easeOutBack(_ t: CGFloat, _ overshoot: CGFloat = 1.7) -> CGFloat {
    let x = clamp(t, 0, 1) - 1
    let c = overshoot
    return 1 + (c + 1) * x * x * x + c * x * x
}

// MARK: - Spring

/// Critically-dampable spring used for every soft motion in the app: body lift,
/// leg placement, look direction, squash. Semi-implicit Euler, stable at 60fps.
struct Spring {
    var value: CGFloat = 0
    var velocity: CGFloat = 0
    var stiffness: CGFloat = 180
    var damping: CGFloat = 18

    init(_ value: CGFloat = 0, stiffness: CGFloat = 180, damping: CGFloat = 18) {
        self.value = value
        self.stiffness = stiffness
        self.damping = damping
    }

    mutating func step(to target: CGFloat, dt: CGFloat) {
        let a = (target - value) * stiffness - velocity * damping
        velocity += a * dt
        value += velocity * dt
    }

    mutating func nudge(_ v: CGFloat) { velocity += v }
    mutating func reset(_ v: CGFloat) { value = v; velocity = 0 }
}

struct Spring2 {
    var value: V2 = .zero
    var velocity: V2 = .zero
    var stiffness: CGFloat = 180
    var damping: CGFloat = 18

    init(_ value: V2 = .zero, stiffness: CGFloat = 180, damping: CGFloat = 18) {
        self.value = value
        self.stiffness = stiffness
        self.damping = damping
    }

    mutating func step(to target: V2, dt: CGFloat) {
        let a = (target - value) * stiffness - velocity * damping
        velocity += a * dt
        value += velocity * dt
    }

    mutating func reset(_ v: V2) { value = v; velocity = .zero }
}

// MARK: - Noise

/// Cheap smooth 1D value noise, used for organic idle jitter.
struct Wobble {
    private var seed: CGFloat
    private var freq: CGFloat

    init(seed: CGFloat = 0, freq: CGFloat = 1) {
        self.seed = seed * 37.13
        self.freq = freq
    }

    func value(_ t: CGFloat) -> CGFloat {
        let x = t * freq + seed
        return (sin(x) * 0.6 + sin(x * 1.87 + 1.3) * 0.3 + sin(x * 4.31 + 2.7) * 0.1)
    }
}

func randRange(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { CGFloat.random(in: lo...hi) }
func chance(_ p: CGFloat) -> Bool { CGFloat.random(in: 0...1) < p }

// MARK: - Geometry

/// Closest point on segment a-b to p, returned as distance along the segment.
func projectOnSegment(_ p: V2, _ a: V2, _ b: V2) -> (t: CGFloat, dist: CGFloat) {
    let ab = b - a
    let l2 = ab.lengthSquared
    if l2 < 1e-9 { return (0, p.distance(to: a)) }
    let t = clamp((p - a).dot(ab) / l2, 0, 1)
    let proj = a + ab * t
    return (t * l2.squareRoot(), p.distance(to: proj))
}

// MARK: - Rope

/// A length of silk as a chain of points. Verlet-integrated, held together
/// by distance constraints that only resist stretching, so a slack line sags
/// and waves run along it while a taut one pulls nearly straight. Either end
/// can be pinned (to the anchor, to the spinnerets) or left to drift.
struct SilkRope {
    private(set) var points: [V2] = []
    private var prev: [V2] = []
    private var acc: CGFloat = 0
    /// The rope's own length; ends further apart than this pull it straight.
    var length: CGFloat = 0
    var tailPinned = true
    private(set) var live = false
    static let segments = 14

    var head: V2 { points.first ?? .zero }
    var tail: V2 { points.last ?? .zero }

    mutating func reset(from a: V2, to b: V2) {
        let n = SilkRope.segments
        points = (0...n).map { V2.lerp(a, b, CGFloat($0) / CGFloat(n)) }
        prev = points
        acc = 0
        length = a.distance(to: b)
        tailPinned = true
        live = true
    }

    mutating func clear() {
        points = []
        prev = []
        live = false
    }

    /// `tail` is ignored when the tail end is not pinned. Gravity is in
    /// world units per second squared, pointing down (-y).
    mutating func step(head: V2, tail: V2, gravity: CGFloat, drag: CGFloat, dt: CGFloat) {
        guard live, points.count > 1 else { return }
        let h: CGFloat = 1.0 / 120.0
        acc += min(dt, 0.05)
        var steps = 0
        while acc >= h, steps < 6 {
            acc -= h
            steps += 1
            substep(head: head, tail: tail, gravity: gravity, drag: drag, h: h)
        }
        // Pin exactly, whatever the substep count, so the ends never float
        // off the things they are tied to.
        points[0] = head
        if tailPinned { points[points.count - 1] = tail }
    }

    private mutating func substep(head: V2, tail: V2, gravity: CGFloat, drag: CGFloat, h: CGFloat) {
        let n = points.count - 1
        points[0] = head
        prev[0] = head
        let last = tailPinned ? n - 1 : n
        if tailPinned { points[n] = tail; prev[n] = tail }
        if last >= 1 {
            let g = V2(0, -gravity) * (h * h)
            for i in 1...last {
                let v = (points[i] - prev[i]) * drag
                prev[i] = points[i]
                points[i] += v + g
            }
        }
        let rest = max(length, 0.01) / CGFloat(n)
        // Silk has a little stiffness of its own: each point is drawn toward
        // the midpoint of its neighbours, hard when the line is taut (so a
        // momentary slack cannot buckle it into loops) and gently when it
        // hangs slack, so it still sags.
        let span = points[0].distance(to: points[n])
        let taut = tailPinned && span > length * 0.96
        let straighten: CGFloat = taut ? 0.16 : 0.05
        // Gauss-Seidel sweeps, alternating direction so neither end wins.
        for it in 0..<10 {
            if it % 2 == 0 {
                for i in 0..<n { relax(i, rest: rest) }
            } else {
                for i in stride(from: n - 1, through: 0, by: -1) { relax(i, rest: rest) }
            }
            if last >= 1 {
                for i in 1...min(last, n - 1) {
                    let mid = (points[i - 1] + points[i + 1]) * 0.5
                    points[i] += (mid - points[i]) * straighten
                }
            }
        }
    }

    private mutating func relax(_ i: Int, rest: CGFloat) {
        let n = points.count - 1
        let d = points[i + 1] - points[i]
        let dist = d.length
        guard dist > rest, dist > 0.0001 else { return }
        let corr = d * ((dist - rest) / dist)
        let aPinned = i == 0
        let bPinned = i + 1 == n && tailPinned
        if aPinned && bPinned { return }
        if aPinned { points[i + 1] -= corr }
        else if bPinned { points[i] += corr }
        else { points[i] += corr * 0.5; points[i + 1] -= corr * 0.5 }
    }
}
