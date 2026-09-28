import AppKit

// MARK: - Building up off the ground
//
// Things can be put together into structures that stand up by themselves:
// a bracket on the back wall holding a branch, a vine tied to the branch,
// a lower branch hung from the vine; two posts with a slab of bark across
// them and a fern on top. Nothing here is CAD — pieces just have a few
// places where they fasten (ports), and while one is dragged, a port that
// comes near one it fits pulls it gently into place.
//
//  • Sticks. Most of the new natural pieces (branches, roots, bamboo,
//    vines) and the rods of the hardware are made of sticks: a smooth line
//    through a few points, thick at one end and thinner at the other. Its
//    outline is both what is painted and what the spider walks on, so the
//    two cannot drift apart (as with every shape; see HabitatGeometry.swift).
//  • Ports. Where a thing fastens: the end of a branch; anywhere along a
//    branch (its middle line); a bracket's cradle; a wall anchor's socket;
//    a hook; the top of a vine; the underside of a platform. `fits` says
//    which go together — the one being held up is the child.
//  • Links. Two ports fastened, kept with the habitat by the things'
//    lasting uids and the ports' names (and where along a line), so they
//    survive saving, loading, resizing and flipping. What is fastened to a
//    thing goes with it when it is moved.
//  • Support. Whether each thing looks held up: on the ground, from the
//    lid, fixed to the back wall, held by something that is, resting on
//    something that is, or propped against it — or floating.
//
// Fastened pieces overlap where they meet (a port is on a thing's middle
// line, or on its top), so the surfaces worked out from their shapes meet
// there too, and the spider can walk from one onto the other.

/// A length of something slender: wood, root, bamboo, a vine, a rod.
struct Stick {
    /// It runs smoothly through these.
    var pts: [V2]
    /// How thick it is at its start, and at its end.
    var w0: CGFloat
    var w1: CGFloat
    var name = "limb"
    /// What each end is, as a place to fasten (nil: nothing fastens there
    /// — the foot of a fork, grown out of its branch).
    var start: HabitatPort.Kind? = .end
    var end: HabitatPort.Kind? = .end

    init(_ pts: [V2], _ w0: CGFloat, _ w1: CGFloat, name: String = "limb", start: HabitatPort.Kind? = .end, end: HabitatPort.Kind? = .end) {
        self.pts = pts
        self.w0 = w0
        self.w1 = w1
        self.name = name
        self.start = start
        self.end = end
    }

    /// The line through its middle, smoothed (a Catmull-Rom curve through
    /// its points), every `step` points or so.
    func spine(step: CGFloat = 4) -> [V2] {
        guard pts.count > 2 else {
            guard pts.count == 2 else { return pts }
            let n = max(1, Int(pts[0].distance(to: pts[1]) / step))
            return (0...n).map { V2.lerp(pts[0], pts[1], CGFloat($0) / CGFloat(n)) }
        }
        var out: [V2] = [pts[0]]
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            let n = max(2, Int(p1.distance(to: p2) / step))
            for k in 1...n {
                let t = CGFloat(k) / CGFloat(n), t2 = t * t, t3 = t2 * t
                let a = p1 * 2
                let b = (p2 - p0) * t
                let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
                let d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
                out.append((a + b + c + d) * 0.5)
            }
        }
        return out
    }

    /// Half its thickness at each point of a spine, tapering along it.
    func halfWidths(_ spine: [V2]) -> [CGFloat] {
        let lens = Stick.cumulative(spine)
        let total = max(lens.last ?? 1, 1e-6)
        return lens.map { lerp(w0, w1, $0 / total) / 2 }
    }

    static func cumulative(_ pts: [V2]) -> [CGFloat] {
        var out: [CGFloat] = [0]
        for i in 1..<max(pts.count, 1) { out.append(out[i - 1] + pts[i].distance(to: pts[i - 1])) }
        return out
    }

    /// Its outline, clockwise: along each side of its spine, and round
    /// over each end.
    func outline() -> [V2] {
        let sp = spine()
        guard sp.count >= 2 else { return [] }
        let hw = halfWidths(sp)
        var left: [V2] = [], right: [V2] = []
        for i in sp.indices {
            let d = (sp[min(i + 1, sp.count - 1)] - sp[max(i - 1, 0)]).normalized
            let n = V2(-d.y, d.x)
            left.append(sp[i] + n * hw[i])
            right.append(sp[i] - n * hw[i])
        }
        // Half way round each end, from one side to the other, in steps
        // small enough that growing it keeps it round (see `Poly.grown`).
        func cap(_ c: V2, from n: V2, _ r: CGFloat) -> [V2] {
            (1...7).map { k in c + n.rotated(by: -CGFloat(k) / 8 * .pi) * r }
        }
        let dEnd = (sp[sp.count - 1] - sp[sp.count - 2]).normalized
        let dStart = (sp[1] - sp[0]).normalized
        let endCap = cap(sp[sp.count - 1], from: V2(-dEnd.y, dEnd.x), hw[hw.count - 1])
        let startCap = cap(sp[0], from: V2(dStart.y, -dStart.x), hw[0])
        return Poly.clockwise(Poly.dedupe(left + endCap + right.reversed() + startCap))
    }

    /// Its outline as a path, for painting.
    func path() -> CGPath {
        let o = outline()
        let p = CGMutablePath()
        guard let f = o.first else { return p }
        p.move(to: f.point)
        for q in o.dropFirst() { p.addLine(to: q.point) }
        p.closeSubpath()
        return p
    }

    /// Its middle line as a port things can fasten anywhere along.
    func along(_ name: String) -> HabitatPort {
        let sp = spine(step: 6)
        return HabitatPort(name: name, kind: .along, pts: sp, half: halfWidths(sp))
    }
}

// MARK: - Ports

/// A place on a thing where another fastens to it, in the world.
struct HabitatPort {
    enum Kind: String {
        /// The end of a branch, a rod, a vine: goes in a cradle or a socket,
        /// or against another branch.
        case end
        /// The foot of something upright: stands on a cradle, a socket, or
        /// on top of something along.
        case foot
        /// Anywhere along something slender (its middle line): a branch to
        /// lay across a cradle, or to fasten other things to.
        case along
        /// Something to rest on: the inside of a bracket's cup, the top of
        /// a shelf bracket or a post. Its point is what rests on it.
        case cradle
        /// A wall anchor: an end or a foot is fixed right in it.
        case socket
        /// The top of something that hangs: from a branch, or a hook.
        case hang
        /// Something to hang things from.
        case hook
        /// The underside of a platform.
        case base
    }

    var name: String
    var kind: Kind
    /// One point — or, along something, its middle line.
    var pts: [V2]
    /// Along something: half its thickness at each point. At an end: half
    /// its thickness there.
    var half: [CGFloat]

    init(name: String, kind: Kind, pts: [V2], half: [CGFloat] = [0]) {
        self.name = name
        self.kind = kind
        self.pts = pts
        self.half = half.isEmpty ? [0] : half
    }

    init(_ name: String, _ kind: Kind, _ p: V2, half: CGFloat = 0) {
        self.init(name: name, kind: kind, pts: [p], half: [half])
    }

    var isLine: Bool { pts.count > 1 }

    /// Whether a child's port of kind `c` fastens to a parent's of kind `p`.
    static func fits(child c: Kind, parent p: Kind) -> Bool {
        switch (c, p) {
        case (.end, .cradle), (.end, .socket), (.end, .along): return true
        case (.foot, .cradle), (.foot, .socket), (.foot, .along): return true
        case (.hang, .along), (.hang, .hook): return true
        case (.base, .cradle), (.base, .along): return true
        case (.along, .cradle), (.along, .hook): return true
        default: return false
        }
    }

    /// Whether what fastens by a child port of this kind lies with its
    /// middle line on the parent (an end, a hanging top, a branch laid in
    /// a cup) rather than sitting on it by its underside (a foot, a base).
    static func centred(_ c: Kind) -> Bool { c == .end || c == .hang || c == .along }

    private var lengths: [CGFloat] { Stick.cumulative(pts) }

    /// A point `f` of the way along it (0…1; a single point is itself).
    func point(at f: CGFloat) -> V2 {
        guard isLine else { return pts[0] }
        let ls = lengths
        let d = clamp(f, 0, 1) * (ls.last ?? 0)
        for i in 1..<pts.count where ls[i] >= d {
            let seg = ls[i] - ls[i - 1]
            return seg < 1e-6 ? pts[i] : V2.lerp(pts[i - 1], pts[i], (d - ls[i - 1]) / seg)
        }
        return pts[pts.count - 1]
    }

    func halfWidth(at f: CGFloat) -> CGFloat {
        guard half.count > 1 else { return half[0] }
        let x = clamp(f, 0, 1) * CGFloat(half.count - 1)
        let i = min(Int(x), half.count - 2)
        return lerp(half[i], half[i + 1], x - CGFloat(i))
    }

    /// Along it, the side facing up at `f` (straight up for a point).
    func up(at f: CGFloat) -> V2 {
        guard isLine else { return V2(0, 1) }
        let a = point(at: max(f - 0.02, 0)), b = point(at: min(f + 0.02, 1))
        let d = (b - a).normalized
        let n = V2(-d.y, d.x)
        return n.y >= 0 ? n : -n
    }

    /// The nearest place on it to `p`: how far along, where, and how far off.
    func nearest(to p: V2, within lo: CGFloat = 0, _ hi: CGFloat = 1) -> (f: CGFloat, point: V2, dist: CGFloat) {
        guard isLine else { return (0, pts[0], pts[0].distance(to: p)) }
        let ls = lengths
        let total = max(ls.last ?? 0, 1e-6)
        var best = (f: CGFloat(0), point: pts[0], dist: CGFloat.greatestFiniteMagnitude)
        for i in 1..<pts.count {
            let (t, d) = projectOnSegment(p, pts[i - 1], pts[i])
            let f = (ls[i - 1] + t) / total
            guard f >= lo - 1e-6, f <= hi + 1e-6, d < best.dist else { continue }
            let seg = max(ls[i] - ls[i - 1], 1e-6)
            best = (f, V2.lerp(pts[i - 1], pts[i], t / seg), d)
        }
        if best.dist == .greatestFiniteMagnitude {
            let f = clamp(lo, 0, 1)
            let q = point(at: f)
            best = (f, q, q.distance(to: p))
        }
        return best
    }

    /// The place on it right over (or under) `p` — where it would lie on
    /// something at `p` — or, if it doesn't pass over `p` at all (it is
    /// upright), the nearest place to it.
    func over(_ p: V2) -> (f: CGFloat, point: V2, dist: CGFloat) {
        guard isLine else { return (0, pts[0], pts[0].distance(to: p)) }
        let ls = lengths
        let total = max(ls.last ?? 0, 1e-6)
        var best: (f: CGFloat, point: V2, dist: CGFloat)?
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            guard (a.x - p.x) * (b.x - p.x) <= 0, abs(b.x - a.x) > 1e-6 else { continue }
            let t = (p.x - a.x) / (b.x - a.x)
            let q = V2.lerp(a, b, t)
            let f = (ls[i - 1] + t * (ls[i] - ls[i - 1])) / total
            guard f >= 0.02, f <= 0.98 else { continue }
            let d = abs(q.y - p.y)
            if best.map({ d < $0.dist }) ?? true { best = (f, q, d) }
        }
        return best ?? nearest(to: p, within: 0.02, 0.98)
    }

    /// Where a child's port — of kind `child`, `childHalf` thick there —
    /// goes when it fastens here, `f` of the way along.
    func seat(for child: Kind, childHalf: CGFloat, at f: CGFloat) -> V2 {
        let q = point(at: f)
        switch kind {
        case .along:
            // An end or a hanging top goes into the middle of it; a foot or
            // a base stands on top of it.
            return HabitatPort.centred(child) ? q : q + up(at: f) * halfWidth(at: f)
        case .cradle:
            // What lies in it lies on it: its middle line that far above.
            return HabitatPort.centred(child) ? q + V2(0, 1) * childHalf : q
        default:
            return q
        }
    }

    func mirrored(about x: CGFloat) -> HabitatPort {
        var p = self
        p.pts = pts.map { V2(2 * x - $0.x, $0.y) }
        return p
    }
}

extension HabitatItem {
    /// Where things fasten to it, where it is in the world (flipped if it is).
    var ports: [HabitatPort] {
        let r = rect
        var ps = kind.definition.ports(r, seed, unit)
        if flipped { ps = ps.map { $0.mirrored(about: r.midX) } }
        return ps
    }

    func port(_ name: String) -> HabitatPort? { ports.first { $0.name == name } }
}

// MARK: - Links

/// Two things fastened together: a port of the child (the one held up) in
/// one of the parent's.
struct HabitatLink: Codable, Equatable {
    var child: String
    var childPort: String
    var parent: String
    var parentPort: String
    /// How far along the parent's port (a line) it is fastened, 0…1.
    var at: CGFloat = 0
    /// How far along the child's own port (laid across a cradle).
    var childAt: CGFloat = 0
}

/// A place a dragged thing would fasten: how far to move it to, and the link.
struct HabitatSnap: Equatable {
    var delta: V2
    var link: HabitatLink
    /// Where the two meet.
    var joint: V2
    static func == (a: HabitatSnap, b: HabitatSnap) -> Bool {
        a.link.parent == b.link.parent && a.link.parentPort == b.link.parentPort && a.link.childPort == b.link.childPort
    }
}

/// What holds a thing up.
enum HabitatSupport: Equatable {
    case ground, lid, wall, glass
    /// Fastened to something that is held up.
    case held(by: Int)
    /// Resting on top of something that is.
    case resting(on: Int)
    /// Propped against, or wedged into, something that is.
    case wedged(in: Int)
    case floating

    var holds: Bool { self != .floating }
}

extension Habitat {
    /// How close (in world points, one to one with the screen) a port has
    /// to come to one it fits before it is pulled into place, and how far
    /// it can then be pulled away before it lets go.
    static let snapRadius: CGFloat = 16
    static let snapHold: CGFloat = 26

    func index(uid: String) -> Int? { items.firstIndex { $0.uid == uid } }

    /// Where a link's two ports are now: the child's, and where it should be.
    func joint(_ l: HabitatLink) -> (child: V2, seat: V2)? {
        guard let c = item(uid: l.child), let p = item(uid: l.parent),
              let cp = c.port(l.childPort), let pp = p.port(l.parentPort) else { return nil }
        if cp.isLine, !pp.isLine {
            // Laid across something: it may slide along its length (a beam
            // made longer stays on both its posts) — wherever it now lies over it.
            let n = cp.over(pp.pts[0])
            return (n.point, pp.seat(for: cp.kind, childHalf: cp.halfWidth(at: n.f), at: l.at))
        }
        let childPoint = cp.point(at: l.childAt)
        return (childPoint, pp.seat(for: cp.kind, childHalf: cp.halfWidth(at: l.childAt), at: l.at).flat(pp, cp.kind, childPoint))
    }

    /// Links whose things or ports are gone, dropped.
    mutating func pruneLinks() {
        let whole = links.filter { joint($0) != nil }
        links = whole
        // (No two the same.)
        var seen = Set<String>()
        links.removeAll { l in
            let k = "\(l.child)|\(l.childPort)|\(l.parent)|\(l.parentPort)"
            defer { seen.insert(k) }
            return seen.contains(k)
        }
    }

    /// What goes with a thing when it moves: what is fastened to it, and
    /// what rests on top of it — and what is fastened to or rests on those
    /// — but only what nothing staying put holds up as well (a plank on two
    /// posts stays with the other post).
    func dependents(of id: Int) -> [Int] {
        var out: [Int] = []
        var moving: Set<String> = []
        guard let first = item(id: id) else { return [] }
        moving.insert(first.uid)
        var changed = true
        while changed {
            changed = false
            for it in items where !moving.contains(it.uid) {
                let held = links.filter { $0.child == it.uid }
                let fastened = !held.isEmpty && held.allSatisfy { moving.contains($0.parent) }
                let resting = held.isEmpty && items.contains { moving.contains($0.uid) && restsOn(it, $0) }
                guard fastened || resting else { continue }
                moving.insert(it.uid)
                out.append(it.id)
                changed = true
            }
        }
        return out
    }

    /// Everything fastened across the edge of what is about to move (`ids`)
    /// let go: what moves lets go of what stays, and what stays of what moves.
    mutating func release(_ ids: [Int]) {
        let uids = Set(ids.compactMap { item(id: $0)?.uid })
        links.removeAll { uids.contains($0.child) != uids.contains($0.parent) }
    }

    /// Whether `a` is resting on the top of `b`.
    func restsOn(_ a: HabitatItem, _ b: HabitatItem) -> Bool {
        guard a.id != b.id, !a.kind.hangs, a.y > 2, a.kind.definition.placement == .rests,
              !links.contains(where: { $0.child == a.uid }),
              b.rect.maxX > a.x - a.w * 0.25, b.rect.minX < a.x + a.w * 0.25,
              let top = Habitat.restingTop(b, from: a.x - a.w * 0.25, to: a.x + a.w * 0.25) else { return false }
        return abs(top - HabitatLayout.ground - a.y) < 2.5
    }

    /// Moves things by `d`, kept in the world.
    mutating func shift(_ ids: [Int], by d: V2) {
        guard d.lengthSquared > 1e-8 else { return }
        let s = size
        for id in ids {
            guard let i = items.firstIndex(where: { $0.id == id }) else { continue }
            items[i].x += d.x
            items[i].y += d.y
            Habitat.clamp(&items[i], in: s)
        }
    }

    /// Every fastened thing moved back onto what it is fastened to (after
    /// its parent was resized, flipped or moved), taking along what goes
    /// with it. Parents first, so a chain settles in one go.
    mutating func realign() {
        for _ in 0..<8 {
            var moved = false
            for l in links {
                guard let j = joint(l), let c = item(uid: l.child) else { continue }
                let d = j.seat - j.child
                guard d.lengthSquared > 1e-4 else { continue }
                shift([c.id] + dependents(of: c.id), by: d)
                moved = true
            }
            if !moved { break }
        }
    }

    /// Unfastens a thing from whatever holds it up.
    mutating func detach(_ id: Int) {
        guard let it = item(id: id) else { return }
        links.removeAll { $0.child == it.uid }
    }

    /// Fastens as a snap says. A point of the child (an end, a foot) is
    /// fastened in one place only; its length may lie on several things.
    mutating func attach(_ link: HabitatLink) {
        let line = item(uid: link.child)?.port(link.childPort)?.isLine ?? false
        links.removeAll { $0.child == link.child && $0.childPort == link.childPort && (!line || $0.parent == link.parent) }
        links.append(link)
    }

    /// Where a thing, as it is now (being dragged), would fasten to
    /// something else: the nearest port of its own within `radius` of one
    /// it fits. `excluding`: what it must not fasten to (itself, and what
    /// goes with it — or it would hold itself up).
    func snap(for it: HabitatItem, excluding: Set<Int>, radius: CGFloat = Habitat.snapRadius) -> HabitatSnap? {
        let mine = it.ports
        guard !mine.isEmpty else { return nil }
        let reach = it.rect.insetBy(dx: -radius - 40, dy: -radius - 40)
        var best: HabitatSnap?
        var bestD = radius
        for o in items where !excluding.contains(o.id) && o.id != it.id {
            let pad = HabitatShape.pad(o.rect.size)
            guard o.rect.insetBy(dx: -pad, dy: -pad).intersects(reach) else { continue }
            for pp in o.ports {
                for cp in mine where HabitatPort.fits(child: cp.kind, parent: pp.kind) {
                    guard let (d, at, childAt, joint) = HabitatPort.meet(child: cp, parent: pp) else { continue }
                    let len = d.length
                    guard len < bestD else { continue }
                    bestD = len
                    best = HabitatSnap(delta: d, link: HabitatLink(child: it.uid, childPort: cp.name, parent: o.uid, parentPort: pp.name,
                                                                    at: at, childAt: childAt), joint: joint)
                }
            }
        }
        return best
    }

    /// Everything a thing's ports are already right on (within `within`),
    /// fastened: what it was let go of on, or put back onto by hand.
    mutating func linkWhatTouches(_ id: Int, within: CGFloat = 1.5) {
        guard let it = item(id: id) else { return }
        let others = Set(dependents(of: id)).union([id])
        let mine = it.ports
        for o in items where !others.contains(o.id) {
            for pp in o.ports {
                for cp in mine where HabitatPort.fits(child: cp.kind, parent: pp.kind) {
                    guard !links.contains(where: { $0.child == it.uid && $0.childPort == cp.name && (!cp.isLine || $0.parent == o.uid) }),
                          let (d, at, childAt, _) = HabitatPort.meet(child: cp, parent: pp), d.length <= within else { continue }
                    links.append(HabitatLink(child: it.uid, childPort: cp.name, parent: o.uid, parentPort: pp.name, at: at, childAt: childAt))
                }
            }
        }
    }

    // MARK: Held up

    /// What holds each thing up, by its number.
    func supports() -> [Int: HabitatSupport] {
        var out: [Int: HabitatSupport] = [:]
        let W = size.width, H = size.height
        for it in items {
            let def = it.kind.definition
            if it.kind.hangs {
                if it.rect.maxY >= H - 2 { out[it.id] = .lid }
            } else if it.y < 2 {
                out[it.id] = .ground
            } else if def.mount == .wall {
                out[it.id] = .wall
            } else if it.rect.minX <= 1 || it.rect.maxX >= W - 1 {
                out[it.id] = .glass
            }
        }
        var geo: [Int: ObjectGeometry] = [:]
        func g(_ it: HabitatItem) -> ObjectGeometry {
            if let x = geo[it.id] { return x }
            let x = it.geometry
            geo[it.id] = x
            return x
        }
        var changed = true
        while changed {
            changed = false
            for it in items where out[it.id] == nil {
                if let l = links.first(where: { $0.child == it.uid && (item(uid: $0.parent).map { out[$0.id] != nil } ?? false) }),
                   let p = item(uid: l.parent) {
                    out[it.id] = .held(by: p.id)
                } else if let p = items.first(where: { out[$0.id] != nil && restsOn(it, $0) }) {
                    out[it.id] = .resting(on: p.id)
                } else if let p = items.first(where: { o in
                    // (Leaning on something that hangs — a vine, a rope — or
                    // on a string of lights holds nothing up.)
                    out[o.id] != nil && o.id != it.id && !o.kind.isBacking && !it.kind.isBacking && !o.kind.hangs
                        && o.kind != .thickVine && o.kind != .stringLights && o.rect.intersects(it.rect.insetBy(dx: -2, dy: -2)) && Habitat.overlaps(g(it), g(o))
                }) {
                    out[it.id] = .wedged(in: p.id)
                } else {
                    continue
                }
                changed = true
            }
        }
        for it in items where out[it.id] == nil { out[it.id] = .floating }
        return out
    }

    func support(of id: Int) -> HabitatSupport { supports()[id] ?? .floating }

    /// Whether something fixed to the back is fixed to a backing wall (a
    /// wooden wall, brickwork… behind it), rather than to the glass.
    func isBacked(_ it: HabitatItem) -> Bool {
        guard it.kind.definition.mount == .wall, !it.kind.isBacking else { return false }
        let p = CGPoint(x: it.rect.midX, y: it.rect.midY)
        return items.contains { $0.kind.isBacking && $0.rect.contains(p) }
    }

    /// Whether two things' solid parts (or, for hardware you can't stand
    /// on, what is drawn of it) overlap.
    static func overlaps(_ a: ObjectGeometry, _ b: ObjectGeometry) -> Bool {
        func solid(_ g: ObjectGeometry) -> [[V2]] { g.parts.isEmpty ? g.visual : g.parts.map(\.outline) }
        let pa = solid(a), pb = solid(b)
        guard !pa.isEmpty, !pb.isEmpty else { return false }
        for x in pa {
            for y in pb {
                guard Poly.bounds(x).intersects(Poly.bounds(y)) else { continue }
                if x.contains(where: { Poly.contains(y, $0) }) || y.contains(where: { Poly.contains(x, $0) }) { return true }
            }
        }
        return false
    }

    // MARK: Supports made for you

    /// Where something coming down from `p` would stand: the top of the
    /// highest solid thing under it (not `excluding`), or the ground.
    func footing(under p: V2, excluding: Set<Int>) -> CGFloat {
        var best = HabitatLayout.ground
        for o in items where !excluding.contains(o.id) && !o.kind.hangs && !o.kind.isBacking && o.kind.climbable
            && o.rect.minX < p.x + 4 && o.rect.maxX > p.x - 4 && o.rect.minY < p.y {
            if let top = Habitat.restingTop(o, from: p.x - 4, to: p.x + 4), top < p.y - 6, top > best { best = top }
        }
        return best
    }

    /// Whether there is a backing wall behind `p`.
    func backing(at p: V2) -> Bool { items.contains { $0.kind.isBacking && $0.rect.contains(p.point) } }

    /// Something to hold a floating thing up, fastened to it: propped from
    /// below — a forked stake under a branch, a post under each end of a
    /// platform — standing on the ground or on whatever is under it; or,
    /// with a backing wall behind, a bracket screwed into that. Only with
    /// neither is it a bracket stuck to the glass at the back. The new
    /// things' numbers (none if it isn't floating, or nothing suits it).
    @discardableResult
    mutating func addSupport(for id: Int) -> [Int] {
        guard let it = item(id: id), support(of: id) == .floating, !it.kind.hangs else { return [] }
        let ports = it.ports
        let shelf = it.kind.definition.shelf
        let natural = [.structures, .vines, .bark, .platforms].contains(shelf)
        // Where it needs holding: which of its ports, how far along, and where.
        var holds: [(port: HabitatPort, f: CGFloat)] = []
        if let l = ports.first(where: { $0.name == "baseL" }), let r = ports.first(where: { $0.name == "baseR" }), l.kind == .base {
            holds = [(l, 0), (r, 0)]
        } else if it.kind == .thickVine || it.kind == .stringLights {
            holds = ports.filter { $0.kind == .end }.map { ($0, 0) }
        } else if let foot = ports.first(where: { $0.kind == .foot }) {
            holds = [(foot, 0)]
        } else if let line = ports.filter({ $0.kind == .along }).max(by: { Stick.cumulative($0.pts).last ?? 0 < Stick.cumulative($1.pts).last ?? 0 }) {
            let len = Stick.cumulative(line.pts).last ?? 0
            holds = (len > 420 ? [0.28, 0.72] : [0.5]).map { (line, $0) }
        }
        guard !holds.isEmpty else { return [] }
        let skip = Set([id] + dependents(of: id))
        var made: [Int] = []
        func put(_ kind: HabitatItemKind, w: CGFloat, h: CGFloat, portName: String, at target: V2, childPort: HabitatPort, f: CGFloat) {
            var hw = HabitatItem(id: nextID, kind: kind, x: 0, y: 0, w: w, h: h, flipped: false, seed: 1 + (it.seed * 31 + made.count * 7) % 9998)
            nextID += 1
            // Placed so that its port is where the child's is.
            guard let pp = hw.port(portName) else { return }
            let seat = pp.seat(for: childPort.kind, childHalf: childPort.halfWidth(at: f), at: 0)
            let d = target - seat
            hw.x += d.x
            hw.y += d.y
            // (Kept in the world — and exactly on the ground, not a hair under it.)
            if abs(hw.y) < 0.01 { hw.y = 0 }
            Habitat.clamp(&hw, in: size)
            items.append(hw)
            links.append(HabitatLink(child: it.uid, childPort: childPort.name, parent: hw.uid, parentPort: portName, at: 0, childAt: f))
            made.append(hw.id)
        }
        for (port, f) in holds {
            let at = port.point(at: f)
            let half = port.halfWidth(at: f)
            // Where the part holding it has to come up to.
            let top = HabitatPort.centred(port.kind) ? at.y - half : at.y
            if backing(at: at) {
                // Screwed into the wall behind it.
                switch port.kind {
                case .base: put(.shelfBracket, w: 56 * clampValue(it.unit, 0.7, 1.6), h: 48 * clampValue(it.unit, 0.7, 1.6), portName: "shelf", at: at, childPort: port, f: f)
                case .foot: put(.wallAnchor, w: 20, h: 20, portName: "socket", at: at, childPort: port, f: f)
                default:
                    let k = clampValue(half / 4.5, 0.75, 2.4)
                    put(.branchBracket, w: 40 * k, h: 44 * k, portName: "cradle", at: at, childPort: port, f: f)
                }
                continue
            }
            let floor = footing(under: at, excluding: skip)
            let rise = top - floor
            if rise >= 20 {
                // Propped up from below.
                if natural {
                    let k = clampValue(half / 3.5, 0.8, 1.6)
                    let w = 30 * k
                    // As tall as the rise to it, and its fork's drop from its top.
                    var h = rise + 24 * k
                    for _ in 0..<4 {
                        let probe = HabitatItem(id: 0, kind: .stake, x: 0, y: 0, w: w, h: h)
                        guard let fork = probe.port("fork") else { break }
                        h = rise + (probe.rect.maxY - fork.pts[0].y)
                    }
                    put(.stake, w: w, h: h, portName: "fork", at: at, childPort: port, f: f)
                } else {
                    let k = clampValue(half / 5, 1, 1.8)
                    put(.verticalSupport, w: 14 * k, h: rise, portName: "top", at: at, childPort: port, f: f)
                }
                continue
            }
            // Nothing to stand on, nor a wall to screw into: stuck to the glass.
            switch port.kind {
            case .base: put(.shelfBracket, w: 56, h: 48, portName: "shelf", at: at, childPort: port, f: f)
            case .foot: put(.wallAnchor, w: 20, h: 20, portName: "socket", at: at, childPort: port, f: f)
            default:
                let k = clampValue(half / 4.5, 0.75, 2.4)
                put(.branchBracket, w: 40 * k, h: 44 * k, portName: "cradle", at: at, childPort: port, f: f)
            }
        }
        // (Placed exactly: the child is already where the new ones hold it.)
        realign()
        return made
    }

    /// Everything floating that a support can be made for, supported.
    mutating func supportFloating() {
        let floating = supports().filter { $0.value == .floating }.map(\.key).sorted()
        for id in floating where support(of: id) == .floating { addSupport(for: id) }
    }
}

extension V2 {
    /// A seat on a flat top (a wall's, a post's): what stands on it may be
    /// anywhere across it, not only at its middle — so a roof or a plank
    /// sits on two walls whatever their spacing, give or take.
    fileprivate func flat(_ pp: HabitatPort, _ child: HabitatPort.Kind, _ childPoint: V2) -> V2 {
        guard pp.kind == .cradle, !HabitatPort.centred(child), pp.half[0] > 0 else { return self }
        return V2(clampValue(childPoint.x, x - pp.half[0], x + pp.half[0]), y)
    }
}

extension HabitatPort {
    /// How a child's port would meet a parent's: how far the child has to
    /// move, how far along each it would be, and where they would meet.
    /// Nil if the two can't meet that way (two lines, say).
    static func meet(child cp: HabitatPort, parent pp: HabitatPort) -> (delta: V2, at: CGFloat, childAt: CGFloat, joint: V2)? {
        switch (cp.isLine, pp.isLine) {
        case (false, false):
            let seat = pp.seat(for: cp.kind, childHalf: cp.half[0], at: 0).flat(pp, cp.kind, cp.pts[0])
            return (seat - cp.pts[0], 0, 0, seat)
        case (false, true):
            // Not right off either end of it.
            let n = pp.nearest(to: cp.pts[0], within: 0.03, 0.97)
            let seat = pp.seat(for: cp.kind, childHalf: cp.half[0], at: n.f)
            return (seat - cp.pts[0], n.f, 0, seat)
        case (true, false):
            let n = cp.over(pp.pts[0])
            let seat = pp.seat(for: cp.kind, childHalf: cp.halfWidth(at: n.f), at: 0)
            return (seat - n.point, 0, n.f, pp.pts[0])
        case (true, true):
            return nil
        }
    }
}

/// (The global `clamp`, where `Habitat.clamp` hides it.)
@inline(__always) func clampValue<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { clamp(v, lo, hi) }

// MARK: - Doors it opens itself

/// The spider lets itself in: walking up to a shut door (at the height of
/// its opening, heading into it), it pushes it open after a moment; once it
/// has gone through and been away from it a little while, the door swings
/// shut again behind it. So a door you have shut stays shut — for
/// everything else, and in the habitat you saved — and it can still come
/// and go. Nothing here touches the spider: the tank opens and shuts the
/// doors, and lays its surfaces out again.
struct DoorKeeper {
    /// Doors it opened, and how long it has been away from each.
    private(set) var opened: [Int: CGFloat] = [:]
    /// How long it has been pushing at each shut door.
    private var pushing: [Int: CGFloat] = [:]
    private var last: V2?

    /// How long it pushes before a door gives, and how long it is away
    /// before one swings shut again.
    static let push: CGFloat = 0.3, linger: CGFloat = 2.5

    /// Each frame, with it at `p` (on a surface or not): the doors to open
    /// now, those to shut, and — a door just opened for it — where it goes
    /// through to (just past the far side of the doorway, on the floor).
    mutating func tend(_ h: Habitat, spider p: V2, attached: Bool, scale: CGFloat, dt: CGFloat) -> (open: [Int], shut: [Int], through: V2?) {
        let v = last.map { p - $0 } ?? .zero
        last = p
        let reach = 22 * scale
        var open: [Int] = [], shut: [Int] = []
        var through: V2?
        for it in h.items where it.kind == .doorClosed {
            guard attached else { pushing[it.id] = nil; continue }
            let r = it.rect
            let (lo, hi) = HabitatShape.opening(.doorClosed, r, it.unit)
            let x0 = r.minX + r.width * 0.35, x1 = r.minX + r.width * 0.65
            // Beside it, at the height of the opening: up against it, or
            // heading into it.
            let side: CGFloat = p.x < (x0 + x1) / 2 ? -1 : 1
            let gap = side < 0 ? x0 - p.x : p.x - x1
            let level = p.y > lo - 4 && p.y < hi
            // Coming along the floor toward it, it swings open a step ahead,
            // and it walks straight on through; up against it anywhere in
            // the doorway, it pushes it open.
            let onFloor = p.y > lo - 4 && p.y < lo + reach * 2.4
            let heading = onFloor && v.x * -side > 0.05 && gap < reach + 36 * scale
            let against = level && gap < reach + 6
            if gap > -reach, heading || against {
                pushing[it.id, default: 0] += dt
                if pushing[it.id]! >= (heading ? DoorKeeper.push * 0.4 : DoorKeeper.push) {
                    open.append(it.id)
                    through = V2((x0 + x1) / 2 - side * ((x1 - x0) / 2 + reach + 40 * scale), lo + reach)
                    opened[it.id] = 0
                    pushing[it.id] = nil
                }
            } else {
                pushing[it.id] = nil
            }
        }
        for (id, away) in opened where !open.contains(id) {
            // (Shut by hand since — or gone — it is no longer its to shut.)
            guard let it = h.item(id: id), it.kind == .door else { opened[id] = nil; continue }
            // (Still in the doorway, or right by it, it stays open.)
            let (lo, hi) = HabitatShape.opening(.door, it.rect, it.unit)
            let x0 = it.rect.minX + it.rect.width * 0.35, x1 = it.rect.minX + it.rect.width * 0.65
            let near = CGRect(x: x0 - reach - 20 * scale, y: lo - reach, width: x1 - x0 + 2 * (reach + 20 * scale), height: hi - lo + 2 * reach).contains(p.point)
            let t = near ? 0 : away + dt
            if t >= DoorKeeper.linger {
                shut.append(id)
                opened[id] = nil
            } else {
                opened[id] = t
            }
        }
        return (open, shut, through)
    }

    /// The doors it left open, all at once (shut again before decorating).
    mutating func release() -> [Int] {
        let ids = Array(opened.keys)
        opened = [:]
        pushing = [:]
        return ids
    }
}
