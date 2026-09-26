import AppKit
import QuartzCore

// MARK: - Traces
//
// What the spider leaves behind it on the desktop. A jumping spider trails
// silk wherever it goes and fastens it where it lands; it spins little
// sheets in sheltered corners; it carries its catch somewhere quiet and
// leaves the husk. Here: strands between the ledges it leapt or dropped
// between, a line it let go of drifting from its ledge, small webs in the
// corners and under ledges, the leftovers of its meals, and the line it
// hitches to a toy to haul it off.
//
// All of it is fastened to the real surfaces (see `SilkPin`) and moves with
// them: a strand between two windows rides along as either is dragged,
// sags as they come together and snaps if they are pulled apart; a window
// closed, or brought in front, tears what was stuck to it; a husk on a
// window's top falls off when the window goes, and lands on whatever is
// below. The pointer can brush through it all — push a strand aside, snap
// it with a quick swipe, tear a web, flick a husk away — and a fly that
// blunders into the silk is caught in it for a while.
//
// Only ever drawn, over the desktop, in a window of its own that takes no
// clicks. Nothing on the real desktop is touched, and it all fades away on
// its own after a few minutes.

/// A spot on a surface something is stuck to: one of the real edges of a
/// loop in the surface map (not the line the spider's body follows), and
/// how far along it.
struct SilkPin {
    var loopID: String
    var edge: Int
    /// How far along the edge, as a share of it: a window resized keeps it
    /// at much the same place on the window.
    var u: CGFloat
    var facing: EdgeFacing
    /// Where it was when last found.
    var last: V2

    /// The nearest open edge to `p` within `within`, taking `prefer`'s edges
    /// over any others that are nearly as near.
    static func at(_ p: V2, map: SurfaceMap, prefer: String? = nil, within: CGFloat = 10) -> SilkPin? {
        var best: (d: CGFloat, pin: SilkPin)?
        for loop in map.loops {
            for (i, e) in loop.edge.enumerated() where e.len > 1 {
                let (t, d0) = projectOnSegment(p, e.a, e.b)
                guard d0 < within else { continue }
                let point = e.point(at: t)
                if loop.kind == .windowEdge, !map.isVisible(point + e.normal * 2, depth: loop.depth) { continue }
                let d = d0 - (loop.id == prefer ? 4 : 0)
                if best == nil || d < best!.d {
                    best = (d, SilkPin(loopID: loop.id, edge: i, u: t / e.len, facing: e.facing, last: point))
                }
            }
        }
        return best?.pin
    }

    struct Found {
        var point: V2
        var normal: V2
        var tangent: V2
        var edgeLength: CGFloat
        /// Of what it is stuck to: a window's, or `Int.min` for the rim of
        /// the screen, the menu bar and the Dock, which are in front of
        /// every window.
        var depth: Int
        /// A window has come over the spot.
        var covered: Bool
    }

    /// Where it is now, or nil once what it was stuck to has gone.
    mutating func find(in map: SurfaceMap) -> Found? {
        guard let loop = map.loop(loopID) else { return nil }
        if !(loop.edge.indices.contains(edge) && loop.edge[edge].facing == facing) {
            // The edges have been renumbered (the Dock came or went): the
            // same one again, if it is still near where it was.
            var best: (d: CGFloat, i: Int, u: CGFloat)?
            for (i, e) in loop.edge.enumerated() where e.facing == facing && e.len > 1 {
                let (t, d) = projectOnSegment(last, e.a, e.b)
                if d < 30, best == nil || d < best!.d { best = (d, i, t / e.len) }
            }
            guard let b = best else { return nil }
            edge = b.i
            u = b.u
        }
        let e = loop.edge[edge]
        var point = e.point(at: u * e.len)
        var normal = e.normal
        if let c = loop.onRoundedCorner(point) { point = c.point; normal = c.normal }
        // Gone somewhere it cannot be followed: another Space, another display.
        guard point.distance(to: last) < 400 else { return nil }
        last = point
        let window = loop.kind == .windowEdge
        return Found(point: point, normal: normal, tangent: e.dir, edgeLength: e.len,
                     depth: window ? loop.depth : Int.min,
                     covered: window && !map.isVisible(point + normal * 2, depth: loop.depth))
    }
}

// MARK: - Strands

/// A length of silk left out on the desktop.
final class Strand {
    enum Kind {
        /// Paid out behind a leap, and fastened where it landed.
        case leap
        /// The line it came down on, left where it stepped off it.
        case hang
        /// Hanging from one end, the other end free.
        case loose
        /// On a toy, the other end on the spider hauling it.
        case tow
        /// Nothing holding it at all: it drifts off as it fades.
        case free
    }
    let id: Int
    var kind: Kind
    var rope = SilkRope()
    /// The end it hangs from (none for a tow, or a free piece).
    var head: SilkPin?
    /// The other end, once it is stuck down.
    var tail: SilkPin?
    /// The head on a toy being towed, rather than on a surface.
    var toyID: Int?
    /// The tail still on the spider: paying out behind a leap, or hauling.
    var spinnerets: V2?
    /// The tail being brought from the spinnerets down onto where it is
    /// stuck, over a moment, rather than jumping there.
    var fastening: (from: V2, k: CGFloat)?
    var age: CGFloat = 0
    var life: CGFloat
    var alpha: CGFloat = 1
    /// Left be once it has come to rest, until something moves it again.
    var asleep = false
    var still: CGFloat = 0
    var dirty = true
    var gone = false
    /// Seconds of a heavy load hanging off it: too long and it gives.
    var strain: CGFloat = 0
    var lastHead = V2.zero
    var lastTail = V2.zero
    var lastTouched: CGFloat = -9
    var breezeIn = randRange(1, 3)
    /// The depth of what each end is stuck to, for telling whether a
    /// window has come between them.
    var headDepth = Int.min
    var tailDepth = Int.min

    init(id: Int, kind: Kind, life: CGFloat) {
        self.id = id
        self.kind = kind
        self.life = life
    }
}

// MARK: - Webs

/// A little web: a sheet of criss-crossed threads across a corner, or a
/// tangle of loops hung under a ledge.
final class Web {
    enum Shape { case corner, underside }
    let id: Int
    let shape: Shape
    /// The corner itself, or the spot under the ledge it hangs from.
    var hub: SilkPin
    /// For a corner, a spot a little way along each side of it: which way
    /// each side runs from the corner.
    var sideA: SilkPin?
    var sideB: SilkPin?
    /// How far it reaches, in world points.
    let size: CGFloat
    /// The threads in its own frame (x along the first side, or along the
    /// ledge; y along the second side, or out from the ledge), in units
    /// of `size`: two ends, how far the middle bows back toward the corner,
    /// and how far it sags under its own weight.
    let threads: [(a: V2, b: V2, bow: CGFloat, sag: CGFloat)]
    var progress: CGFloat = 0
    var damage: CGFloat = 0
    var age: CGFloat = 0
    var life: CGFloat
    var alpha: CGFloat = 1
    /// A window has come over the spot it is stuck to.
    var hidden = false
    var dirty = true
    var gone = false
    let seed = Int.random(in: 0..<10_000)
    /// Where it is: the corner point and its two axes in the world.
    var frame: (o: V2, x: V2, y: V2)?
    var lastTouched: CGFloat = -9

    init(id: Int, shape: Shape, hub: SilkPin, sideA: SilkPin?, sideB: SilkPin?, size: CGFloat, life: CGFloat) {
        self.id = id
        self.shape = shape
        self.hub = hub
        self.sideA = sideA
        self.sideB = sideB
        self.size = size
        self.life = life
        threads = shape == .corner ? Web.cornerThreads() : Web.undersideThreads()
    }

    /// Arcs from side to side, growing outward from the corner, a few
    /// lines straight out of it, and some criss-crossing any old how.
    private static func cornerThreads() -> [(a: V2, b: V2, bow: CGFloat, sag: CGFloat)] {
        var out: [(a: V2, b: V2, bow: CGFloat, sag: CGFloat)] = []
        for k in 0..<6 {
            let r = 0.28 + CGFloat(k) * 0.14
            out.append((V2(r * randRange(0.85, 1.15), 0), V2(0, r * randRange(0.85, 1.15)), randRange(0.15, 0.35), randRange(1, 4)))
            if k == 1 || k == 3 {
                let s = randRange(0.5, 1.0)
                out.append((V2(0.03, 0.03), V2(s * randRange(0.35, 0.6), s * randRange(0.35, 0.6)), 0, 0))
            }
        }
        for _ in 0..<4 {
            out.append((V2(randRange(0.15, 1.0), 0), V2(0, randRange(0.15, 1.0)), randRange(-0.1, 0.2), randRange(0, 3)))
        }
        return out
    }

    /// Loops hung between spots along the ledge, a few drooping V's, and
    /// ties between them.
    private static func undersideThreads() -> [(a: V2, b: V2, bow: CGFloat, sag: CGFloat)] {
        var out: [(a: V2, b: V2, bow: CGFloat, sag: CGFloat)] = []
        for _ in 0..<6 {
            let a1 = randRange(-1, 0.45)
            let a2 = min(a1 + randRange(0.35, 1.0), 1)
            out.append((V2(a1, 0), V2(a2, 0), 0, randRange(0.2, 0.62)))
        }
        for _ in 0..<3 {
            let a = randRange(-0.8, 0.6)
            let tip = V2(a + randRange(0.05, 0.25), randRange(0.35, 0.7))
            out.append((V2(a, 0), tip, 0, 0))
            out.append((tip, V2(tip.x + randRange(0.05, 0.25), 0), 0, 0))
        }
        for _ in 0..<3 {
            out.append((V2(randRange(-0.7, 0), randRange(0.1, 0.3)), V2(randRange(0, 0.7), randRange(0.1, 0.3)), 0, randRange(0.02, 0.1)))
        }
        return out
    }

    /// Thread `k` has come apart under the pointer.
    func torn(_ k: Int) -> Bool {
        let f = CGFloat(((seed + k * 7919) % 97)) / 97
        return damage > 0.1 + f * 0.85
    }

    /// How many threads are spun so far.
    var laid: Int { min(threads.count, Int((progress * CGFloat(threads.count)).rounded(.up))) }

    /// A point of its own frame in the world.
    func world(_ l: V2) -> V2? {
        guard let f = frame else { return nil }
        return f.o + f.x * (l.x * size) + f.y * (l.y * size)
    }

    /// Thread `k` in the world: its ends and the control point of its curve.
    func curve(_ k: Int) -> (a: V2, c: V2, b: V2)? {
        guard let f = frame, let a = world(threads[k].a), let b = world(threads[k].b) else { return nil }
        let th = threads[k]
        var c = (a + b) * 0.5
        switch shape {
        case .corner:
            // Bowed back toward the corner, then down a little under its
            // weight — but never out through either side.
            c = f.o + (c - f.o) * (1 - th.bow) + V2(0, -th.sag * size * 0.08)
            let la = max((c - f.o).dot(f.x), 1), lb = max((c - f.o).dot(f.y), 1)
            c = f.o + f.x * la + f.y * lb
        case .underside:
            c += f.y * (th.sag * size * 2)
        }
        return (a, c, b)
    }
}

// MARK: - Leftovers

/// What is left of a meal: a pair of wings, the two halves of a shell.
final class Leftover {
    let id: Int
    let kind: PreyKind
    let image: CGImage
    let size: CGSize
    var pos: V2
    var vel = V2.zero
    var angle: CGFloat
    var spin: CGFloat = 0
    /// The ledge it lies on; nil while it falls.
    var rest: SilkPin?
    /// Pushed along its ledge, px/s.
    var slide: CGFloat = 0
    /// How far its middle sits off the ledge.
    let lift: CGFloat
    let tilt = randRange(-0.25, 0.25)
    var age: CGFloat = 0
    var life: CGFloat
    var alpha: CGFloat = 1
    var hidden = false
    var dirty = true
    var gone = false

    init(id: Int, kind: PreyKind, image: CGImage, size: CGSize, at p: V2, life: CGFloat) {
        self.id = id
        self.kind = kind
        self.image = image
        self.size = size
        self.pos = p
        self.life = life
        angle = randRange(-0.4, 0.4)
        lift = size.height * 0.22
    }

    var moving: Bool { rest == nil || slide != 0 }
}

// MARK: - The keeper

/// Everything left about the desktop, and the physics of it.
final class TraceKeeper {
    let map: SurfaceMap
    weak var toyBox: ToyBox?
    /// Off, nothing is left, and anything there is goes at once.
    var enabled = true {
        didSet { if !enabled { clear() } }
    }
    var scale: CGFloat = 1
    /// Silk was set atremble — plucked, torn, a fly caught in it — where,
    /// and how hard (0…1): the spider feels it.
    var onTremble: ((V2, CGFloat) -> Void)?

    private(set) var strands: [Strand] = []
    private(set) var webs: [Web] = []
    private(set) var leftovers: [Leftover] = []
    private var nextID = 1
    private var t: CGFloat = 0
    private var cursorWas: V2?
    private var cursorVel = V2.zero
    private var spiderWas: V2?
    private var coverCheckIn: CGFloat = 0

    /// A fly stuck in the silk.
    private struct Snag {
        let prey: Int
        let trace: Int
        /// On a strand, which stretch of it and how far along; in a web,
        /// where in its frame.
        var at: V2
        var until: CGFloat
    }
    private var snags: [Snag] = []
    /// Flies just out of the silk, and until when they cannot be caught again.
    private var freed: [Int: CGFloat] = [:]

    /// The most out at once — strands, webs and leftovers together — or nil
    /// for no limit. Past it, the oldest start to fade.
    var limit: Int? = 12 {
        didSet { if limit != oldValue { makeRoom() } }
    }

    init(map: SurfaceMap) {
        self.map = map
    }

    var isEmpty: Bool { strands.isEmpty && webs.isEmpty && leftovers.isEmpty }
    /// Anything moving: a line swaying, a husk falling or sliding, a fly
    /// struggling.
    var astir: Bool {
        strands.contains { !$0.asleep } || leftovers.contains { $0.moving } || !snags.isEmpty
    }

    func has(_ id: Int) -> Bool { strands.contains { $0.id == id && !$0.gone } || webs.contains { $0.id == id && !$0.gone } }
    func strand(_ id: Int) -> Strand? { strands.first { $0.id == id && !$0.gone } }
    func web(_ id: Int) -> Web? { webs.first { $0.id == id && !$0.gone } }

    /// A web anywhere near `p`.
    func webNear(_ p: V2, within r: CGFloat) -> Bool {
        webs.contains { w in (w.frame?.o ?? w.hub.last).distance(to: p) < r }
    }

    /// Takes everything away.
    func clear() {
        strands = []
        webs = []
        leftovers = []
        snags = []
    }

    private func newID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Too many out: the oldest of them start to go.
    private func makeRoom() {
        guard let most = limit else { return }
        // Everything out and not already on its way: a line still on the
        // spider, and the scraps of a snapped one drifting off, don't count.
        let fading: CGFloat = 4.5
        var out: [(age: CGFloat, fade: () -> Void)] = []
        for s in strands where s.spinnerets == nil && s.kind != .free && !s.gone && s.life - s.age > fading {
            out.append((s.age, { s.life = min(s.life, s.age + 4) }))
        }
        for w in webs where !w.gone && w.life - w.age > fading {
            out.append((w.age, { w.life = min(w.life, w.age + 4) }))
        }
        for l in leftovers where !l.gone && l.life - l.age > fading {
            out.append((l.age, { l.life = min(l.life, l.age + 4) }))
        }
        guard out.count > most else { return }
        // The oldest go first.
        for item in out.sorted(by: { $0.age > $1.age }).prefix(out.count - most) { item.fade() }
    }

    // MARK: Leaving silk

    /// A line paid out from a spot on a ledge to the spinnerets, as it
    /// leaps: fastened where it lands (`fasten`), or let go (`letGo`).
    func beginLine(from pin: SilkPin, tail: V2) -> Int? {
        guard enabled else { return nil }
        var p = pin
        guard let f = p.find(in: map) else { return nil }
        let s = Strand(id: newID(), kind: .leap, life: randRange(150, 260))
        s.head = p
        s.headDepth = f.depth
        s.spinnerets = tail
        s.rope.reset(from: f.point, to: tail)
        s.lastHead = f.point
        s.lastTail = tail
        strands.append(s)
        return s.id
    }

    /// The spinnerets have moved on: more line comes out behind them, and
    /// on a tow the toy comes after.
    func payOut(_ id: Int, tail: V2) {
        strand(id)?.spinnerets = tail
    }

    /// Stuck down where it has landed.
    func fasten(_ id: Int, to pin: SilkPin) {
        guard let s = strand(id), let from = s.spinnerets else { return }
        var p = pin
        guard let f = p.find(in: map) else { letGo(id); return }
        s.spinnerets = nil
        s.tail = p
        s.tailDepth = f.depth
        s.fastening = (from, 0)
        s.kind = .leap
        // A little slack, so it sags between the two.
        s.rope.length = max(s.rope.head.distance(to: f.point) * randRange(1.03, 1.1), 8)
        s.asleep = false
        makeRoom()
    }

    /// The spider's end comes away: it hangs from its other end — the
    /// ledge, or the toy — and drifts there as it fades.
    func letGo(_ id: Int) {
        guard let s = strand(id) else { return }
        s.spinnerets = nil
        s.fastening = nil
        if s.head == nil, s.toyID == nil {
            loosen(s, free: true)
            return
        }
        s.rope.tailPinned = false
        s.kind = s.toyID != nil ? .tow : .loose
        s.life = min(s.life, s.age + (s.toyID != nil ? randRange(8, 14) : randRange(25, 45)))
        s.asleep = false
    }

    /// A line the spider was on, left behind as it is: from a spot on a
    /// ledge, just as it hangs, to where it stepped off onto something (or
    /// hanging free, if it let go of it in the air).
    @discardableResult
    func leaveLine(_ points: [V2], from pin: SilkPin, to end: SilkPin?) -> Int? {
        guard enabled, points.count >= 2 else { return nil }
        var h = pin
        guard let fh = h.find(in: map) else { return nil }
        var pts = points
        pts[0] = fh.point
        let s = Strand(id: newID(), kind: end == nil ? .loose : .hang, life: end == nil ? randRange(30, 50) : randRange(150, 260))
        s.head = h
        s.headDepth = fh.depth
        if var e = end, let fe = e.find(in: map) {
            s.tail = e
            s.tailDepth = fe.depth
            s.fastening = (pts[pts.count - 1], 0)
        }
        s.rope.reset(along: pts)
        if s.tail == nil { s.rope.tailPinned = false }
        // Kept as long as it lies, with a touch of give.
        s.rope.length *= 1.01
        s.lastHead = fh.point
        s.lastTail = pts[pts.count - 1]
        strands.append(s)
        makeRoom()
        return s.id
    }

    /// A line hitched to a toy, the other end on the spinnerets: it tows
    /// the toy as it walks off.
    func beginTow(toy: Toy, tail: V2) -> Int? {
        guard enabled else { return nil }
        let s = Strand(id: newID(), kind: .tow, life: 60)
        s.toyID = toy.id
        s.spinnerets = tail
        s.rope.reset(from: toy.pos, to: tail)
        s.rope.length = toy.pos.distance(to: tail) + 3 * scale
        s.lastHead = toy.pos
        s.lastTail = tail
        strands.append(s)
        return s.id
    }

    /// Still hitched to its toy, and the toy still there to haul.
    func towing(_ id: Int) -> Bool {
        guard let s = strand(id), let tid = s.toyID, s.spinnerets != nil else { return false }
        return toyBox?.toy(tid) != nil
    }

    // MARK: Spinning a web

    /// Starts a web across a corner (`corner` the point where two sides
    /// meet, `a` and `b` a spot along each) or under a ledge at `hub`.
    func startWeb(corner: V2, a: V2, b: V2) -> Int? {
        guard enabled, let hub = SilkPin.at(corner, map: map, within: 6),
              let pa = SilkPin.at(a, map: map, within: 6), let pb = SilkPin.at(b, map: map, within: 6) else { return nil }
        let size = min(corner.distance(to: a), corner.distance(to: b))
        let w = Web(id: newID(), shape: .corner, hub: hub, sideA: pa, sideB: pb, size: size, life: randRange(480, 720))
        webs.append(w)
        makeRoom()
        return w.id
    }

    func startWeb(under p: V2, size: CGFloat) -> Int? {
        guard enabled, let hub = SilkPin.at(p, map: map, within: 6), hub.facing == .down else { return nil }
        let w = Web(id: newID(), shape: .underside, hub: hub, sideA: nil, sideB: nil, size: size, life: randRange(480, 720))
        webs.append(w)
        makeRoom()
        return w.id
    }

    /// A little more of it spun.
    func spin(_ id: Int, by amount: CGFloat) {
        guard let w = web(id) else { return }
        let was = w.laid
        w.progress = min(1, w.progress + amount)
        if w.laid != was { w.dirty = true }
    }

    // MARK: Leftovers

    /// What is left of a meal, dropped where it was eaten.
    func leaveLeftover(of kind: PreyKind, at p: V2, facing: CGFloat) {
        guard enabled, let art = LeftoverArt.image(for: kind, scale: scale) else { return }
        let l = Leftover(id: newID(), kind: kind, image: art.image, size: art.size, at: p, life: randRange(180, 300))
        l.vel = V2(facing * randRange(10, 40), randRange(20, 60))
        l.spin = randRange(-3, 3)
        leftovers.append(l)
        makeRoom()
    }

    // MARK: Frame

    /// `spider`: where it is, if it is out on the desktop, for husks it
    /// walks into.
    func update(dt: CGFloat, cursor: V2, prey: [Prey], spider: V2?, spiderGrounded: Bool) {
        t += dt
        let move = cursorWas.map { cursor - $0 } ?? .zero
        let c0 = cursorWas ?? cursor
        cursorWas = cursor
        if dt > 0 { cursorVel = approach(cursorVel, move / dt, 20, dt) }
        let spiderVel = (spider.flatMap { s in spiderWas.map { (s - $0) / max(dt, 0.001) } } ?? .zero).clampedLength(900)
        spiderWas = spider
        guard !isEmpty else { snags = []; return }
        coverCheckIn -= dt
        let checkCover = coverCheckIn <= 0
        if checkCover { coverCheckIn = 0.25 }
        // (A jump of the pointer — back from hiding, onto another display —
        // is not a sweep through everything in between.)
        let wipe = move.length > 0.3 && move.length < 400 ? (c0, cursor) : nil

        for s in strands where !s.gone { updateStrand(s, dt: dt, wipe: wipe, checkCover: checkCover) }
        for w in webs where !w.gone { updateWeb(w, dt: dt, wipe: wipe) }
        for l in leftovers where !l.gone {
            updateLeftover(l, dt: dt, wipe: wipe,
                           spider: spiderGrounded ? spider : nil, spiderVel: spiderVel)
        }
        updateSnags(dt: dt, prey: prey)
        strands.removeAll { $0.gone }
        webs.removeAll { $0.gone }
        leftovers.removeAll { $0.gone }
    }

    /// How faded something is at `age` of `life`: in over a moment, out
    /// over the last few seconds.
    private func fade(_ age: CGFloat, _ life: CGFloat, over: CGFloat = 5) -> CGFloat {
        clamp((life - age) / over, 0, 1)
    }

    // MARK: Strands

    private func updateStrand(_ s: Strand, dt: CGFloat, wipe: (V2, V2)?, checkCover: Bool) {
        s.age += dt
        if s.age >= s.life { s.gone = true; return }
        let a = fade(s.age, s.life, over: s.kind == .free ? 1.5 : 5)
        if abs(a - s.alpha) > 0.004 { s.alpha = a; s.dirty = true }

        // Where its ends are now.
        var headPoint: V2?
        var headCovered = false
        if let id = s.toyID {
            if let toy = toyBox?.toy(id), !toy.held {
                headPoint = toy.pos
            } else {
                // Taken off it (picked up, put away): the line comes away.
                s.toyID = nil
                loosen(s, free: true)
                return
            }
        } else if var pin = s.head {
            if let f = pin.find(in: map) {
                s.head = pin
                headPoint = f.point
                headCovered = f.covered
                s.headDepth = f.depth
            } else {
                s.head = nil
            }
        }
        var tailPoint: V2?
        var tailCovered = false
        if let sp = s.spinnerets {
            tailPoint = sp
            if s.kind == .leap {
                // Paying out behind it as it flies: taut, and never short.
                s.rope.length = max(s.rope.length, s.rope.head.distance(to: sp) * 1.01)
            }
        } else if var pin = s.tail {
            if let f = pin.find(in: map) {
                s.tail = pin
                tailPoint = f.point
                tailCovered = f.covered
                s.tailDepth = f.depth
                if var fz = s.fastening {
                    fz.k = min(1, fz.k + dt / 0.3)
                    tailPoint = V2.lerp(fz.from, f.point, smoothstep(fz.k))
                    s.fastening = fz.k >= 1 ? nil : fz
                }
            } else {
                s.tail = nil
            }
        }

        // What it was stuck to has gone, or a window has come over the
        // spot: it comes unstuck there.
        let headLost = (s.head == nil && s.toyID == nil && s.kind != .free) || (checkCover && headCovered)
        let tailLost = (s.spinnerets == nil && s.tail == nil && s.rope.tailPinned && s.kind != .free) || (checkCover && tailCovered)
        if headLost || tailLost {
            if headLost && tailLost { loosen(s, free: true); return }
            if headLost {
                // Hangs from the other end instead.
                if s.spinnerets != nil || s.tail == nil { loosen(s, free: true); return }
                flip(s)
            } else {
                s.tail = nil
            }
            s.rope.tailPinned = false
            s.kind = .loose
            s.life = min(s.life, s.age + randRange(20, 40))
            s.asleep = false
            onTremble?(tailLost ? s.lastTail : s.lastHead, 0.4)
            return
        }

        // A window brought forward between its two ends cuts through it.
        if checkCover, s.spinnerets == nil, s.rope.tailPinned, s.rope.points.count > 4 {
            let behind = min(s.headDepth, s.tailDepth)
            for i in [s.rope.points.count / 3, s.rope.points.count / 2, 2 * s.rope.points.count / 3]
            where map.depth(at: s.rope.points[i]) < behind {
                snap(s, at: i)
                return
            }
        }

        // The pointer through it: a push aside, or — quick enough — a snap.
        var touched = false
        if let (c0, c1) = wipe, s.rope.live {
            let move = c1 - c0
            let reach = 6 * max(scale, 0.7)
            let pts = s.rope.points
            let quick = move.length / max(dt, 0.001) > 2400 * max(scale, 0.7)
            for i in 0..<(pts.count - 1) {
                let (d, w) = segmentGap(c0, c1, pts[i], pts[i + 1])
                guard d < reach else { continue }
                if quick, s.kind != .free, s.rope.tailPinned || s.head != nil {
                    snap(s, at: w < 0.5 ? i : i + 1)
                    onTremble?(pts[i], 0.8)
                    return
                }
                let along = (pts[i + 1] - pts[i]).normalized
                let push = (move - along * move.dot(along)).clampedLength(12 * max(scale, 0.7)) * 0.8
                s.rope.push(i, by: push * (1 - w))
                s.rope.push(i + 1, by: push * w)
                touched = true
            }
            if touched, t - s.lastTouched > 0.6 {
                s.lastTouched = t
                onTremble?(c1, 0.35)
            }
        }

        // On a toy, the line hauls it along after the spider.
        if let id = s.toyID, let toy = toyBox?.toy(id), let tail = tailPoint, s.spinnerets != nil {
            let pull = toy.haul(from: tail, length: s.rope.length, map: map)
            // A toy hanging off the line and swinging on it is a load: the
            // heavier it is, the sooner the line gives.
            if toy.airborne, pull > 1 {
                s.strain += dt * toy.kind.mass
            } else {
                s.strain = max(0, s.strain - dt)
            }
            if s.strain > 1.1 {
                s.toyID = nil
                loosen(s, free: true)
                onTremble?(toy.pos, 0.6)
                return
            }
            headPoint = toy.pos
        }

        // Physics, while there is anything to move it.
        let h = headPoint ?? s.rope.head
        let tl = tailPoint ?? s.rope.tail
        let endsMoved = h.distance(to: s.lastHead) > 0.05 || tl.distance(to: s.lastTail) > 0.05
        s.lastHead = h
        s.lastTail = tl
        var restless = touched || endsMoved || s.spinnerets != nil || s.toyID != nil || s.fastening != nil
            || !s.rope.headPinned
        if !s.rope.tailPinned {
            // A loose end on the air: a breath of it now and then.
            s.breezeIn -= dt
            if s.breezeIn <= 0 {
                s.breezeIn = randRange(1.5, 4)
                let gust = V2(randRange(-1, 1), randRange(-0.2, 0.5)) * randRange(1, 3)
                for i in (s.rope.points.count / 2)..<s.rope.points.count { s.rope.push(i, by: gust * CGFloat(i) / CGFloat(s.rope.points.count)) }
                restless = true
            }
        }
        if restless { s.asleep = false; s.still = 0 }
        guard !s.asleep else { return }
        let free = !s.rope.tailPinned
        s.rope.step(head: h, tail: tl, gravity: free ? 240 : (s.spinnerets != nil ? 700 : 520),
                    drag: free ? 0.985 : 0.972, dt: dt)
        s.dirty = true
        if s.rope.motion < 0.015, !restless {
            s.still += dt
            if s.still > 0.8 { s.asleep = true }
        } else if s.rope.motion >= 0.015 {
            s.still = 0
        }

        // Pulled apart — the windows it joins dragged away from each
        // other, or the pointer pushing it too far — it snaps.
        if s.spinnerets == nil, s.rope.tailPinned, s.rope.headPinned {
            let stretched = h.distance(to: tl) > s.rope.length * 1.3 || s.rope.pathLength > s.rope.length * 1.5
            if stretched {
                var worst = (i: s.rope.points.count / 2, d: CGFloat(0))
                if let (_, c1) = wipe {
                    for i in s.rope.points.indices {
                        let d = -s.rope.points[i].distance(to: c1)
                        if worst.d == 0 || d > worst.d { worst = (i, d) }
                    }
                }
                snap(s, at: worst.i)
            }
        }
    }

    /// Swaps the ends round, so what was the tail is now what it hangs from.
    private func flip(_ s: Strand) {
        let pts = Array(s.rope.points.reversed())
        let len = s.rope.length
        s.rope.reset(along: pts)
        s.rope.length = len
        s.head = s.tail
        s.headDepth = s.tailDepth
        s.tail = nil
        s.fastening = nil
        s.lastHead = pts.first ?? .zero
    }

    /// Comes unstuck: hanging from its head if it still has one, or free
    /// altogether, drifting off as it fades.
    private func loosen(_ s: Strand, free: Bool) {
        s.spinnerets = nil
        s.fastening = nil
        s.rope.tailPinned = false
        if free || (s.head == nil) {
            s.kind = .free
            s.head = nil
            s.rope.headPinned = false
            s.life = min(s.life, s.age + 1.5)
        } else {
            s.kind = .loose
            s.life = min(s.life, s.age + randRange(20, 40))
        }
        s.asleep = false
        s.dirty = true
    }

    /// Breaks at point `k`: each side hangs from whatever it was stuck to,
    /// and anything left with nothing to hang from drifts off.
    private func snap(_ s: Strand, at k0: Int) {
        let pts = s.rope.points
        s.gone = true
        guard pts.count >= 3 else { return }
        let k = clamp(k0, 1, pts.count - 2)
        let left = Array(pts[0...k]), right = Array(pts[k...].reversed())
        for (side, pin, depth) in [(left, s.toyID == nil ? s.head : nil, s.headDepth),
                                   (right, s.spinnerets == nil ? s.tail : nil, s.tailDepth)] {
            let piece = Strand(id: newID(), kind: pin == nil ? .free : .loose,
                               life: pin == nil ? 1.5 : randRange(20, 40))
            piece.rope.reset(along: side)
            piece.rope.tailPinned = false
            if let p = pin {
                piece.head = p
                piece.headDepth = depth
            } else {
                piece.rope.headPinned = false
            }
            piece.alpha = s.alpha
            piece.lastHead = side.first ?? .zero
            strands.append(piece)
        }
        makeRoom()
        onTremble?(pts[k], 0.7)
    }

    // MARK: Webs

    private func updateWeb(_ w: Web, dt: CGFloat, wipe: (V2, V2)?) {
        w.age += dt
        if w.age >= w.life { w.gone = true; return }
        let a = fade(w.age, w.life, over: w.damage >= 1 ? 0.6 : 5)
        if abs(a - w.alpha) > 0.004 { w.alpha = a; w.dirty = true }
        guard let f = w.hub.find(in: map) else {
            // What it was stuck to has gone: it goes too.
            w.life = min(w.life, w.age + 0.6)
            return
        }
        var frame: (o: V2, x: V2, y: V2)
        switch w.shape {
        case .corner:
            guard var sa = w.sideA, var sb = w.sideB, let fa = sa.find(in: map), let fb = sb.find(in: map) else {
                w.life = min(w.life, w.age + 0.6)
                return
            }
            w.sideA = sa
            w.sideB = sb
            frame = (f.point, (fa.point - f.point).normalized, (fb.point - f.point).normalized)
        case .underside:
            frame = (f.point, f.tangent, f.normal)
        }
        if w.frame.map({ $0.o.distance(to: frame.o) > 0.05 || $0.x.distance(to: frame.x) > 0.001 || $0.y.distance(to: frame.y) > 0.001 }) ?? true {
            w.frame = frame
            w.dirty = true
        }
        if f.covered != w.hidden { w.hidden = f.covered; w.dirty = true }

        // The pointer swept through it tears it — a slow one only stirs it.
        if let (c0, c1) = wipe, !w.hidden, w.progress > 0.05 {
            let centre = frame.o + (frame.x + frame.y) * (w.shape == .corner ? w.size * 0.4 : 0) + frame.y * (w.shape == .underside ? w.size * 0.3 : 0)
            let r = w.size * (w.shape == .corner ? 0.75 : 1.0)
            let (d, _) = segmentGap(c0, c1, centre, centre)
            let speed = (c1 - c0).length / max(dt, 0.001)
            if d < r, speed > 200 {
                w.damage = min(1, w.damage + (c1 - c0).length / (w.size * 5))
                w.dirty = true
                if w.damage >= 1 { w.life = min(w.life, w.age + 0.6) }
                if t - w.lastTouched > 0.5 {
                    w.lastTouched = t
                    onTremble?(centre, 0.5)
                }
            }
        }
    }

    // MARK: Leftovers

    private func updateLeftover(_ l: Leftover, dt: CGFloat, wipe: (V2, V2)?, spider: V2?, spiderVel: V2) {
        l.age += dt
        if l.age >= l.life { l.gone = true; return }
        let a = fade(l.age, l.life)
        if abs(a - l.alpha) > 0.004 { l.alpha = a; l.dirty = true }
        let before = (l.pos, l.angle, l.hidden)

        if var pin = l.rest {
            if let f = pin.find(in: map) {
                // Brushed along by a spider walking into it.
                if let sp = spider, sp.distance(to: l.pos) < (l.size.width * 0.5 + 10 * scale), spiderVel.length > 15 {
                    let along = spiderVel.dot(f.tangent)
                    if along * (l.pos - sp).dot(f.tangent) > 0, abs(along) > abs(l.slide) {
                        l.slide = along * 1.1
                    }
                }
                if l.slide != 0 {
                    pin.u += l.slide * dt / max(f.edgeLength, 1)
                    l.slide = approach(l.slide, 0, 5, dt)
                    if abs(l.slide) < 2 { l.slide = 0 }
                    l.angle += l.slide * dt * 0.02
                }
                if pin.u < 0 || pin.u > 1 {
                    // Off the end of its ledge.
                    l.rest = nil
                    l.vel = f.tangent * l.slide
                    l.spin = -l.slide * 0.05
                    l.slide = 0
                } else {
                    l.rest = pin
                    l.hidden = f.covered
                    l.pos = f.point + f.normal * l.lift
                    l.angle = approach(l.angle, f.tangent.angle + l.tilt, 6, dt)
                }
            } else {
                // What it lay on has gone: it falls.
                l.rest = nil
                l.vel = .zero
                l.hidden = false
            }
        } else {
            fall(l, dt: dt)
        }

        // Flicked away by the pointer.
        if let (c0, c1) = wipe, !l.hidden {
            let (d, _) = segmentGap(c0, c1, l.pos, l.pos)
            if d < l.size.width * 0.4 + 5, cursorVel.length > 160 {
                l.rest = nil
                l.slide = 0
                l.vel = cursorVel.clampedLength(900) * 0.45 + V2(0, 160)
                l.spin = randRange(-9, 9)
            }
        }
        if l.pos.distance(to: before.0) > 0.02 || abs(l.angle - before.1) > 0.002 || l.hidden != before.2 { l.dirty = true }
    }

    private func fall(_ l: Leftover, dt: CGFloat) {
        l.vel.y -= 1100 * dt
        l.vel *= exp(-0.9 * dt)
        let from = l.pos
        l.pos += l.vel * dt
        l.angle += l.spin * dt
        l.spin *= exp(-1.5 * dt)
        // Onto the top of the first thing it comes down on.
        var best: (y: CGFloat, loop: SurfaceLoop, i: Int, t: CGFloat)?
        for loop in map.loops {
            for (i, e) in loop.edge.enumerated() where e.facing == .up && e.len > 1 {
                let y = e.a.y + l.lift
                guard from.y >= y - 0.5, l.pos.y < y else { continue }
                let f = (from.y - y) / max(from.y - l.pos.y, 0.0001)
                let x = from.x + (l.pos.x - from.x) * f
                guard x >= min(e.a.x, e.b.x) - 1, x <= max(e.a.x, e.b.x) + 1 else { continue }
                if loop.kind == .windowEdge, !map.isVisible(V2(x, e.a.y + 2), depth: loop.depth) { continue }
                if best == nil || y > best!.y { best = (y, loop, i, projectOnSegment(V2(x, e.a.y), e.a, e.b).t) }
            }
        }
        if let b = best {
            let e = b.loop.edge[b.i]
            l.pos.y = b.y
            if l.vel.y < -300 {
                // A little bounce first.
                l.vel = V2(l.vel.x * 0.5, -l.vel.y * 0.25)
                l.spin = -l.spin * 0.5 + randRange(-2, 2)
            } else {
                l.rest = SilkPin(loopID: b.loop.id, edge: b.i, u: b.t / max(e.len, 1), facing: e.facing, last: e.point(at: b.t))
                l.slide = l.vel.dot(e.dir) * 0.3
                l.vel = .zero
                l.spin = 0
            }
        }
        // Down past the bottom of every screen: gone.
        if l.pos.y < map.worldBounds.minY - 40 || !map.worldBounds.insetBy(dx: -200, dy: -200).contains(l.pos.point) {
            l.gone = true
        }
    }

    // MARK: Caught in the silk

    private func updateSnags(dt: CGFloat, prey: [Prey]) {
        for (id, until) in freed where until < t { freed[id] = nil }
        // Still stuck, until it struggles free — or the spider comes for it.
        snags = snags.compactMap { sn in
            guard let p = prey.first(where: { $0.id == sn.prey }), p.state == .loose, !p.held else { return nil }
            guard t < sn.until, let at = snagPoint(sn) else {
                breakFree(sn, prey: p)
                return nil
            }
            // Struggling: it jerks about on the spot, and the silk shakes.
            let jig = V2(sin(t * 31 + CGFloat(sn.prey)) * 1.2, cos(t * 23 + CGFloat(sn.prey)) * 0.8) * max(scale, 0.7)
            p.pos = at + jig
            p.vel = .zero
            if let s = strand(sn.trace) {
                let i = Int(sn.at.x)
                s.rope.push(i, by: jig * 0.3)
                s.rope.push(i + 1, by: -jig * 0.3)
                s.asleep = false
            }
            if chance(dt * 0.4) { onTremble?(at, 0.5) }
            return sn
        }
        // Blundering into the silk.
        for p in prey where p.kind.flies && p.state == .loose && !p.held && !p.onSurface && p.alpha > 0.5 && freed[p.id] == nil
            && !snags.contains(where: { $0.prey == p.id }) {
            let from = p.pos - p.vel * dt
            if let sn = snagFor(from: from, to: p.pos, prey: p) {
                snags.append(sn)
                onTremble?(p.pos, 0.9)
            }
        }
    }

    private func snagFor(from a: V2, to b: V2, prey p: Prey) -> Snag? {
        let reach = 4 * max(scale, 0.7) + p.kind.catchRadius * p.scale * 0.15
        for s in strands where s.kind != .free && s.alpha > 0.3 && s.rope.live {
            let pts = s.rope.points
            for i in 0..<(pts.count - 1) {
                let (d, w) = segmentGap(a, b, pts[i], pts[i + 1])
                if d < reach, chance(0.7) {
                    return Snag(prey: p.id, trace: s.id, at: V2(CGFloat(i), w), until: t + randRange(5, 11))
                }
            }
        }
        for w in webs where !w.hidden && w.laid > 3 && w.damage < 0.7 {
            guard let f = w.frame else { continue }
            let l = V2((b - f.o).dot(f.x), (b - f.o).dot(f.y)) / max(w.size, 1)
            let inside: Bool
            switch w.shape {
            case .corner: inside = l.x > 0.05 && l.y > 0.05 && l.x + l.y < 1.05 * w.progress
            case .underside: inside = abs(l.x) < 0.95 && l.y > 0.05 && l.y < 0.65
            }
            if inside, chance(0.85) {
                return Snag(prey: p.id, trace: w.id, at: l, until: t + randRange(6, 13))
            }
        }
        return nil
    }

    private func snagPoint(_ sn: Snag) -> V2? {
        if let s = strand(sn.trace) {
            let i = clamp(Int(sn.at.x), 0, s.rope.points.count - 2)
            return V2.lerp(s.rope.points[i], s.rope.points[i + 1], sn.at.y)
        }
        if let w = web(sn.trace), !w.hidden { return w.world(sn.at) }
        return nil
    }

    /// Out of it at last, the silk the worse for it.
    private func breakFree(_ sn: Snag, prey p: Prey) {
        freed[p.id] = t + 3
        p.vel = V2(randRange(-80, 80), randRange(60, 140))
        if let s = strand(sn.trace), chance(0.35) { snap(s, at: Int(sn.at.x) + 1) }
        if let w = web(sn.trace) {
            w.damage = min(1, w.damage + 0.15)
            w.dirty = true
        }
    }

    /// Tools only: stick a creature in the silk right now, if it is near any.
    func debugSnag(_ p: Prey) -> Bool {
        guard let sn = snagFor(from: p.pos + V2(0, 12), to: p.pos - V2(0, 12), prey: p) ?? snagFor(from: p.pos + V2(12, 0), to: p.pos - V2(12, 0), prey: p) else { return false }
        snags.append(sn)
        return true
    }

    /// Whether a creature is stuck in the silk.
    func isSnagged(_ id: Int) -> Bool { snags.contains { $0.prey == id } }

    /// Tools only: a line of what is out.
    var debugSummary: String {
        let kinds = strands.map { "\($0.kind)" }.joined(separator: ",")
        return "strands \(strands.count) [\(kinds)] webs \(webs.count) leftovers \(leftovers.count) snags \(snags.count)"
    }
}

/// How near two segments come (a segment of zero length is a point), and
/// how far along the second the nearest spot is, 0…1.
func segmentGap(_ p0: V2, _ p1: V2, _ q0: V2, _ q1: V2) -> (dist: CGFloat, along: CGFloat) {
    let r = p1 - p0, s = q1 - q0
    let denom = r.cross(s)
    if abs(denom) > 1e-9 {
        let u = (q0 - p0).cross(r) / denom
        let v = (q0 - p0).cross(s) / denom
        if u >= 0, u <= 1, v >= 0, v <= 1 { return (0, u) }
    }
    let sl = max(s.length, 0.0001)
    var best = (dist: CGFloat.greatestFiniteMagnitude, along: CGFloat(0))
    for p in [p0, p1] {
        let (tt, d) = projectOnSegment(p, q0, q1)
        if d < best.dist { best = (d, tt / sl) }
    }
    for (q, along) in [(q0, CGFloat(0)), (q1, CGFloat(1))] {
        let d = projectOnSegment(q, p0, p1).dist
        if d < best.dist { best = (d, along) }
    }
    return best
}

// MARK: - Leftover pictures

enum LeftoverArt {
    /// What is left of a meal of `kind`, lying flat, drawn once: the image
    /// and its size in world points. Nothing much is left of some.
    static func image(for kind: PreyKind, scale: CGFloat) -> (image: CGImage, size: CGSize)? {
        guard [.fruitFly, .moth, .mosquito, .beetle, .cricket].contains(kind) else { return nil }
        let unit = max(scale, 0.4) * 1.7
        let size = CGSize(width: 22 * unit, height: 12 * unit)
        let px: CGFloat = 2
        let w = Int((size.width * px).rounded(.up)), h = Int((size.height * px).rounded(.up))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: px, y: px)
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: unit, y: unit)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let ink = CGColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 0.75)
        func wing(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ angle: CGFloat, fill: CGColor, veins: Int) {
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: angle)
            ctx.setFillColor(fill)
            ctx.setStrokeColor(CGColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 0.55))
            ctx.setLineWidth(0.35)
            let r = CGRect(x: 0, y: -ry, width: rx * 2, height: ry * 2)
            ctx.addEllipse(in: r)
            ctx.drawPath(using: .fillStroke)
            for v in 0..<veins {
                let f = CGFloat(v + 1) / CGFloat(veins + 1)
                ctx.move(to: CGPoint(x: 0.3, y: 0))
                ctx.addLine(to: CGPoint(x: rx * 1.7, y: (f - 0.5) * ry * 1.4))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        switch kind {
        case .fruitFly:
            let glass = CGColor(red: 0.84, green: 0.88, blue: 0.93, alpha: 0.6)
            wing(CGPoint(x: -1, y: 0), 3.2, 1.4, 2.7, fill: glass, veins: 2)
            wing(CGPoint(x: 0.5, y: -0.6), 3.2, 1.4, 0.35, fill: glass, veins: 2)
            ctx.setFillColor(CGColor(red: 0.45, green: 0.2, blue: 0.1, alpha: 0.8))
            ctx.fillEllipse(in: CGRect(x: -0.9, y: -1.6, width: 1.6, height: 1.2))
        case .mosquito:
            let glass = CGColor(red: 0.85, green: 0.87, blue: 0.9, alpha: 0.55)
            wing(CGPoint(x: -0.5, y: 0.3), 3.8, 0.9, 3.0, fill: glass, veins: 1)
            wing(CGPoint(x: 0.5, y: -0.4), 3.8, 0.9, 0.2, fill: glass, veins: 1)
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(0.3)
            ctx.move(to: CGPoint(x: -1, y: -1.5)); ctx.addLine(to: CGPoint(x: -4.5, y: -0.6)); ctx.addLine(to: CGPoint(x: -8, y: -2.2))
            ctx.move(to: CGPoint(x: 1.2, y: -1.8)); ctx.addLine(to: CGPoint(x: 4.8, y: -0.9)); ctx.addLine(to: CGPoint(x: 7.6, y: -2.4))
            ctx.strokePath()
        case .moth:
            let dust = CGColor(red: 0.64, green: 0.57, blue: 0.47, alpha: 0.92)
            let band = CGColor(red: 0.78, green: 0.72, blue: 0.62, alpha: 0.9)
            for (c, ang) in [(CGPoint(x: -1.2, y: 0), CGFloat(2.9)), (CGPoint(x: 0.8, y: -0.8), CGFloat(0.15))] {
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: ang)
                let p = CGMutablePath()
                p.move(to: .zero)
                p.addCurve(to: CGPoint(x: 7.5, y: 1.6), control1: CGPoint(x: 2, y: 3.2), control2: CGPoint(x: 5.5, y: 3))
                p.addCurve(to: .zero, control1: CGPoint(x: 6.5, y: -1.8), control2: CGPoint(x: 2.5, y: -1.8))
                ctx.addPath(p)
                ctx.setFillColor(dust)
                ctx.setStrokeColor(CGColor(red: 0.35, green: 0.3, blue: 0.24, alpha: 0.6))
                ctx.setLineWidth(0.35)
                ctx.drawPath(using: .fillStroke)
                ctx.setFillColor(band)
                ctx.fillEllipse(in: CGRect(x: 3.4, y: 0.2, width: 2.4, height: 1.1))
                ctx.setFillColor(CGColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 0.7))
                ctx.fillEllipse(in: CGRect(x: 5.2, y: 1.0, width: 0.8, height: 0.8))
                ctx.restoreGState()
            }
        case .beetle:
            let shell = CGColor(red: 0.22, green: 0.16, blue: 0.12, alpha: 1)
            for (c, ang, flip) in [(CGPoint(x: -3.2, y: 0.2), CGFloat(0.35), CGFloat(1)), (CGPoint(x: 3.0, y: -0.2), CGFloat(-0.25), CGFloat(-1))] {
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: ang)
                ctx.scaleBy(x: flip, y: 1)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -3, y: -1.4))
                p.addCurve(to: CGPoint(x: 3.2, y: -1.2), control1: CGPoint(x: -1.5, y: 2.6), control2: CGPoint(x: 2.2, y: 2.4))
                p.closeSubpath()
                ctx.addPath(p)
                ctx.setFillColor(shell)
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(0.4)
                ctx.drawPath(using: .fillStroke)
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
                ctx.fillEllipse(in: CGRect(x: -1.2, y: 0, width: 2.4, height: 0.7))
                ctx.restoreGState()
            }
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(0.45)
            ctx.move(to: CGPoint(x: -0.6, y: -1.4)); ctx.addLine(to: CGPoint(x: 0.8, y: -0.4)); ctx.addLine(to: CGPoint(x: 2.2, y: -1.6))
            ctx.strokePath()
        case .cricket:
            let husk = CGColor(red: 0.55, green: 0.48, blue: 0.3, alpha: 0.85)
            ctx.saveGState()
            ctx.rotate(by: -0.1)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -5, y: -1.2))
            p.addLine(to: CGPoint(x: -1.5, y: 1.2)); p.addLine(to: CGPoint(x: 1.2, y: 0.4))
            p.addLine(to: CGPoint(x: 4.5, y: 1.4)); p.addLine(to: CGPoint(x: 3.6, y: -1.3)); p.closeSubpath()
            ctx.addPath(p)
            ctx.setFillColor(husk)
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(0.35)
            ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()
            // A hind leg.
            ctx.setStrokeColor(CGColor(red: 0.3, green: 0.24, blue: 0.12, alpha: 0.9))
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: -7.5, y: -1.8)); ctx.addLine(to: CGPoint(x: -3.2, y: 2.4)); ctx.addLine(to: CGPoint(x: -1.6, y: -1.9))
            ctx.strokePath()
        default:
            break
        }
        guard let img = ctx.makeImage() else { return nil }
        return (img, size)
    }
}

// MARK: - View

/// Screen-sized, click-through: the silk and the leftovers, one layer each,
/// redrawn only when they change.
final class TraceView: NSView {
    var worldOrigin = CGPoint.zero
    /// Each line twice: a faint dark edge under the silk, so it shows on
    /// white as well as on dark (a shadow would be redrawn off screen every
    /// time the line moves).
    private var strandLayers: [Int: (edge: CAShapeLayer, silk: CAShapeLayer)] = [:]
    private var webLayers: [Int: (sheet: CAShapeLayer, edge: CAShapeLayer, threads: CAShapeLayer)] = [:]
    private var leftoverLayers: [Int: CALayer] = [:]
    private let webGroup = CALayer()
    private let strandGroup = CALayer()
    private let leftoverGroup = CALayer()
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        for g in [webGroup, strandGroup, leftoverGroup] {
            g.actions = ["sublayers": NSNull()]
            layer?.addSublayer(g)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let noActions: [String: CAAction] = ["path": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
                                                        "position": NSNull(), "transform": NSNull(), "bounds": NSNull(),
                                                        "contents": NSNull()]

    private func silkLayer(width: CGFloat, alpha: CGFloat, dark: Bool = false) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.fillColor = nil
        l.lineCap = .round
        l.lineJoin = .round
        l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        l.actions = TraceView.noActions
        l.strokeColor = dark ? CGColor(red: 0, green: 0, blue: 0, alpha: alpha) : CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
        l.lineWidth = width
        return l
    }

    /// Brings every layer up to date with what is out there.
    func apply(_ k: TraceKeeper) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let o = V2(worldOrigin.x, worldOrigin.y)

        var live = Set<Int>()
        for s in k.strands where s.rope.live {
            live.insert(s.id)
            let l: (edge: CAShapeLayer, silk: CAShapeLayer)
            if let have = strandLayers[s.id] { l = have } else {
                l = (silkLayer(width: 2.2, alpha: 0.16, dark: true), silkLayer(width: 0.85, alpha: 0.5))
                strandGroup.addSublayer(l.edge)
                strandGroup.addSublayer(l.silk)
                strandLayers[s.id] = l
                s.dirty = true
            }
            guard s.dirty else { continue }
            s.dirty = false
            let path = TraceView.strandPath(s, origin: o)
            l.edge.path = path
            l.silk.path = path
            l.edge.opacity = Float(s.alpha)
            l.silk.opacity = Float(s.alpha)
        }
        for (id, l) in strandLayers where !live.contains(id) {
            l.edge.removeFromSuperlayer()
            l.silk.removeFromSuperlayer()
            strandLayers[id] = nil
        }

        live = []
        for w in k.webs {
            live.insert(w.id)
            let pair: (sheet: CAShapeLayer, edge: CAShapeLayer, threads: CAShapeLayer)
            if let have = webLayers[w.id] { pair = have } else {
                let sheet = CAShapeLayer()
                sheet.actions = TraceView.noActions
                sheet.fillColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.05)
                sheet.strokeColor = nil
                pair = (sheet, silkLayer(width: 1.9, alpha: 0.14, dark: true), silkLayer(width: 0.7, alpha: 0.5))
                webGroup.addSublayer(pair.sheet)
                webGroup.addSublayer(pair.edge)
                webGroup.addSublayer(pair.threads)
                webLayers[w.id] = pair
                w.dirty = true
            }
            guard w.dirty else { continue }
            w.dirty = false
            let paths = TraceView.webPaths(w, origin: o)
            pair.threads.path = paths.threads
            pair.edge.path = paths.threads
            pair.sheet.path = paths.sheet
            let a = Float(w.hidden ? 0 : w.alpha)
            pair.threads.opacity = a
            pair.edge.opacity = a
            pair.sheet.opacity = a * Float(1 - w.damage * 0.8)
        }
        for (id, pair) in webLayers where !live.contains(id) {
            pair.sheet.removeFromSuperlayer()
            pair.edge.removeFromSuperlayer()
            pair.threads.removeFromSuperlayer()
            webLayers[id] = nil
        }

        live = []
        for lo in k.leftovers {
            live.insert(lo.id)
            let l: CALayer
            if let have = leftoverLayers[lo.id] { l = have } else {
                l = CALayer()
                l.actions = TraceView.noActions
                l.contents = lo.image
                l.contentsScale = 2
                l.bounds = CGRect(origin: .zero, size: lo.size)
                leftoverGroup.addSublayer(l)
                leftoverLayers[lo.id] = l
                lo.dirty = true
            }
            guard lo.dirty else { continue }
            lo.dirty = false
            l.position = (lo.pos - o).point
            l.setAffineTransform(CGAffineTransform(rotationAngle: lo.angle))
            l.opacity = Float(lo.hidden ? 0 : lo.alpha)
        }
        for (id, l) in leftoverLayers where !live.contains(id) {
            l.removeFromSuperlayer()
            leftoverLayers[id] = nil
        }
        CATransaction.commit()
    }

    /// Through the rope's points, smoothly, with a little tuft of silk
    /// where each end is stuck down.
    static func strandPath(_ s: Strand, origin: V2) -> CGPath {
        let p = CGMutablePath()
        let pts = s.rope.points.map { $0 - origin }
        guard pts.count >= 2 else { return p }
        p.move(to: pts[0].point)
        let n = pts.count
        for i in 0..<(n - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, n - 1)]
            p.addCurve(to: p2.point, control1: (p1 + (p2 - p0) / 6).point, control2: (p2 - (p3 - p1) / 6).point)
        }
        func tuft(_ a: V2, _ seed: Int) {
            for i in 0..<3 {
                let ang = CGFloat(i) * 2.1 + 0.5 + CGFloat(seed % 7) * 0.2
                p.move(to: a.point)
                p.addLine(to: CGPoint(x: a.x + cos(ang) * 3.5, y: a.y + sin(ang) * 2.5))
            }
        }
        if s.head != nil { tuft(pts[0], s.id) }
        if s.tail != nil, s.fastening == nil { tuft(pts[n - 1], s.id + 3) }
        return p
    }

    static func webPaths(_ w: Web, origin: V2) -> (threads: CGPath, sheet: CGPath) {
        let threads = CGMutablePath(), sheet = CGMutablePath()
        guard let f = w.frame else { return (threads, sheet) }
        let laid = w.laid
        for k in 0..<laid {
            guard let c = w.curve(k) else { continue }
            let a = (c.a - origin).point, b = (c.b - origin).point, ctl = (c.c - origin).point
            if w.torn(k) {
                // Come apart: the two ends droop from where they were stuck.
                for (from, to) in [(a, b), (b, a)] {
                    let tip = CGPoint(x: from.x + (to.x - from.x) * 0.3, y: from.y + (to.y - from.y) * 0.3 - 5)
                    threads.move(to: from)
                    threads.addQuadCurve(to: tip, control: CGPoint(x: from.x + (to.x - from.x) * 0.2, y: from.y))
                }
                continue
            }
            threads.move(to: a)
            threads.addQuadCurve(to: b, control: ctl)
            // A faint film where the threads lie close: each span fills its
            // bit, so it is thickest where they overlap.
            if w.threads[k].a.y == 0 || w.shape == .corner {
                sheet.move(to: a)
                sheet.addQuadCurve(to: b, control: ctl)
                if w.shape == .corner { sheet.addLine(to: (f.o - origin).point) }
                sheet.closeSubpath()
            }
        }
        // Where it is stuck down.
        let anchors: [V2] = w.shape == .corner ? [f.o] : [f.o - f.x * (w.size * 0.6), f.o + f.x * (w.size * 0.5)]
        for (i, a0) in anchors.enumerated() where laid > 0 {
            let a = a0 - origin
            for j in 0..<3 {
                let ang = CGFloat(i * 3 + j) * 2.1 + CGFloat(w.seed % 5) * 0.3
                threads.move(to: a.point)
                threads.addLine(to: CGPoint(x: a.x + cos(ang) * 3, y: a.y + sin(ang) * 3))
            }
        }
        return (threads, sheet)
    }
}
