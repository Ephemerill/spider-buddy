import AppKit

// MARK: - The physical shape of things
//
// What the spider walks on in the tank is worked out from the shapes of
// the things in it — not from boxes round them. Every kind of thing says,
// in its definition (HabitatObjects.swift), what it is made of, as parts:
//
//  • bulk: something solid and chunky — a stone, a log, a pot, the trunk
//    of a cactus. Whatever touches it joins it: the ground runs up one
//    side of a stone, over its top and down the other, as one surface.
//  • limb: something slender — a branch, a stem, a stalk, a vine, a
//    leaf. It keeps its own surface, all the way round it. Where it runs
//    into something bulky it ends there, on it; where it crosses another
//    limb, or passes over something bulky, the two just meet: a junction,
//    where the spider may step from one onto the other.
//
// Each part is an outline, taken from the same paths its picture is
// painted with (the shared ones are in `HabitatShape` below), so the
// surface is where the picture is. Around the parts a thing may also have
// a hollow inside (with its mouth), anchor points (a flat top to sit on, a
// spot to tie silk to, a way in), and parts that are only there to look at
// — foliage and flowers it cannot stand on.
//
// `HabitatSurfaces` turns a habitat's things into the map's loops: every
// outline grown by the height of the body (the line its middle follows),
// the ground and the glass and the lid round them, bulk run together with
// whatever it touches, and the junctions between limbs and everything else.

/// One solid part of a thing, as the spider meets it: its outline, all the
/// way round, clockwise (solid on the right, the way the map's loops run).
struct ShapePart {
    enum Role {
        /// Chunky: what touches it runs into it (see the top of the file).
        case bulk
        /// Slender: keeps its own surface, and meets others at junctions.
        case limb
    }
    /// What it is — "body", "stalk", "stem", "leaf"… — for anyone looking.
    var name: String
    var role: Role
    var outline: [V2]
}

/// A particular spot on a thing.
struct ObjectAnchor {
    enum Kind {
        /// Somewhere flat on top, to sit.
        case perch
        /// An underside or an end to fasten silk to.
        case tie
        /// The way into a hollow.
        case entrance
        /// Deep inside something that covers it: where it would hide.
        case refuge
        /// At the edge of water, to drink.
        case drink
        /// A warm top to sit in the light.
        case bask
        /// The highest seat, to look out from.
        case lookout
        /// Where food is put.
        case feed
    }
    var kind: Kind
    var point: V2
    /// Out from the surface there.
    var normal: V2
}

/// Room inside something: the inside of a hollow log. Its outline and its
/// mouth are known; nothing walks in there yet.
struct Hollow {
    var cavity: [V2]
    /// The lip of its mouth, where it would step in.
    var mouth: V2
    /// Which way is in.
    var inward: V2
}

/// A thing's physical shape, in world points.
struct ObjectGeometry {
    var parts: [ShapePart] = []
    var hollows: [Hollow] = []
    var anchors: [ObjectAnchor] = []
    /// Drawn, but nothing there to stand on: foliage, flowers, a tuft of
    /// leaves at the end of a twig.
    var visual: [[V2]] = []

    var walkable: Bool { !parts.isEmpty }

    /// Everything, mirrored side to side about `x` (a flipped thing).
    func mirrored(about x: CGFloat) -> ObjectGeometry {
        func m(_ p: V2) -> V2 { V2(2 * x - p.x, p.y) }
        func poly(_ ps: [V2]) -> [V2] { ps.map(m).reversed() }
        var g = ObjectGeometry()
        g.parts = parts.map { ShapePart(name: $0.name, role: $0.role, outline: poly($0.outline)) }
        g.hollows = hollows.map { Hollow(cavity: poly($0.cavity), mouth: m($0.mouth), inward: V2(-$0.inward.x, $0.inward.y)) }
        g.anchors = anchors.map { ObjectAnchor(kind: $0.kind, point: m($0.point), normal: V2(-$0.normal.x, $0.normal.y)) }
        g.visual = visual.map(poly)
        return g
    }

    /// Every point moved.
    func mapped(_ f: (V2) -> V2) -> ObjectGeometry {
        var g = self
        g.parts = parts.map { ShapePart(name: $0.name, role: $0.role, outline: $0.outline.map(f)) }
        g.hollows = hollows.map { Hollow(cavity: $0.cavity.map(f), mouth: f($0.mouth), inward: $0.inward) }
        g.anchors = anchors.map { ObjectAnchor(kind: $0.kind, point: f($0.point), normal: $0.normal) }
        g.visual = visual.map { $0.map(f) }
        return g
    }

    /// Round what it can stand on.
    var bounds: CGRect {
        parts.reduce(CGRect.null) { $0.union(Poly.bounds($1.outline)) }
    }

    /// The top of its solid parts between `lo` and `hi` across: the highest
    /// point of any of them there, if any of them is there at all.
    func top(from lo: CGFloat, to hi: CGFloat) -> CGFloat? {
        var best: CGFloat?
        for part in parts {
            let o = part.outline
            for i in o.indices {
                let a = o[i], b = o[(i + 1) % o.count]
                let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
                guard x1 >= lo, x0 <= hi else { continue }
                // The segment within the range: its higher end there.
                var ys: [CGFloat] = []
                for p in [a, b] where p.x >= lo && p.x <= hi { ys.append(p.y) }
                if abs(b.x - a.x) > 1e-6 {
                    for x in [lo, hi] where x > x0 && x < x1 { ys.append(a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)) }
                }
                if let m = ys.max(), best.map({ m > $0 }) ?? true { best = m }
            }
        }
        return best
    }

    /// The lines along its tops, left to right, sampled every `step` points
    /// — one for each stretch with something under it: what is on the upper
    /// side of it, where snow would settle.
    func topLines(step: CGFloat = 6) -> [[V2]] {
        let b = bounds
        guard !b.isNull, b.width > 1 else { return [] }
        let n = max(2, Int(b.width / step))
        let half = b.width / CGFloat(n) * 0.5
        var out: [[V2]] = [[]]
        for k in 0...n {
            let x = b.minX + b.width * CGFloat(k) / CGFloat(n)
            if let y = top(from: x - half, to: x + half) {
                out[out.count - 1].append(V2(x, y))
            } else if !out[out.count - 1].isEmpty {
                out.append([])
            }
        }
        return out.filter { $0.count >= 2 }
    }

    /// Whether `p` is on it — on something solid of it, or within `slack` of
    /// that — or in its foliage.
    func contains(_ p: V2, slack: CGFloat = 0) -> Bool {
        for part in parts where Poly.contains(part.outline, p) || (slack > 0 && Poly.distance(part.outline, p) < slack) { return true }
        for v in visual where Poly.contains(v, p) { return true }
        return false
    }
}

extension HabitatItem {
    /// Its physical shape, where it is in the world: flipped if it is, and
    /// — standing on the ground or hanging from the lid — sunk a little way
    /// into what holds it, so that where the two meet is a clean crossing
    /// and not two lines lying along each other.
    var geometry: ObjectGeometry {
        let r = rect
        var g = kind.definition.shape(r, seed, unit)
        if flipped { g = g.mirrored(about: r.midX) }
        // Only what is painted: its picture stops at the room round it.
        let painted = r.insetBy(dx: -HabitatShape.pad(r.size), dy: -HabitatShape.pad(r.size))
        g.parts = g.parts.compactMap { p in
            let o = Poly.clip(p.outline, to: painted)
            return o.count >= 3 && abs(Poly.area(o)) > 1 ? ShapePart(name: p.name, role: p.role, outline: o) : nil
        }
        g.visual = g.visual.map { Poly.clip($0, to: painted) }.filter { $0.count >= 3 }
        if onGround {
            let lip = r.minY + 3
            g.parts = g.parts.map { ShapePart(name: $0.name, role: $0.role, outline: $0.outline.map { $0.y < lip ? V2($0.x, r.minY - 3) : $0 }) }
        } else if kind.hangs {
            let lip = r.maxY - 3
            g.parts = g.parts.map { ShapePart(name: $0.name, role: $0.role, outline: $0.outline.map { $0.y > lip ? V2($0.x, r.maxY + 3) : $0 }) }
        }
        return g
    }
}

// MARK: - Shapes shared with the pictures

/// The paths things are painted with that are also their physical shape,
/// in one place, so the two cannot drift apart; and each kind's shape.
enum HabitatShape {
    static func rnd(_ seed: Int, _ i: Int) -> CGFloat {
        let x = sin(CGFloat(seed) * 12.9898 + CGFloat(i) * 78.233) * 43758.5453
        return x - floor(x)
    }

    /// Room round a thing's rectangle in its picture — for leaves that spill
    /// over, its shadow, and its sway. Nothing beyond it is painted, so
    /// nothing beyond it is there to stand on.
    static func pad(_ size: CGSize) -> CGFloat { max(10, min(size.width, size.height) * 0.14) }

    /// How much bigger than it comes a thing standing in `r` is drawn.
    static func unit(_ kind: HabitatItemKind, _ r: CGRect) -> CGFloat {
        max(0.5, min(r.width / kind.defaultSize.width, r.height / kind.defaultSize.height))
    }

    // MARK: Wood

    static func logBody(_ r: CGRect) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
    }

    /// The end of a hollow log: its rim, and the dark way in inside it.
    static func logHole(_ r: CGRect, u: CGFloat) -> (rim: CGRect, inside: CGRect) {
        let endW = r.height * 0.46
        let hole = CGRect(x: r.minX + 2 * u, y: r.minY + r.height * 0.06, width: endW, height: r.height * 0.88)
        return (hole, hole.insetBy(dx: hole.width * 0.14, dy: hole.height * 0.12))
    }

    /// The line of a branch: from its low end up to its tip, with a bend
    /// (the bend is the control point of the curves it is drawn with).
    static func branchLine(_ r: CGRect, flipped: Bool = false) -> [V2] {
        let a = V2(r.minX + r.width * 0.04, r.minY + r.height * 0.1)
        let m = V2(r.minX + r.width * 0.48, r.minY + r.height * 0.52)
        let b = V2(r.maxX - r.width * 0.05, r.minY + r.height * 0.86)
        let pts = [a, m, b]
        return flipped ? pts.map { V2(r.maxX + r.minX - $0.x, $0.y) }.reversed() : pts
    }

    /// A branch's thickness at its foot and its tip.
    static func branchWidths(_ r: CGRect, u: CGFloat) -> (base: CGFloat, tip: CGFloat) {
        (max(6 * u, r.height * 0.1), max(3 * u, r.height * 0.045))
    }

    /// The tapering limb of a branch: each side of its line, smoothed, and
    /// a rounded tip.
    static func branchLimb(_ r: CGRect, u: CGFloat) -> CGPath {
        let pts = branchLine(r).map(\.point)
        let (base, tip) = branchWidths(r, u: u)
        func side(_ sign: CGFloat) -> [CGPoint] {
            var out: [CGPoint] = []
            for (i, p) in pts.enumerated() {
                let a = i == 0 ? pts[0] : pts[i - 1], b = i == pts.count - 1 ? pts[i] : pts[i + 1]
                let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
                let len = max(hypot(d.x, d.y), 0.001)
                let n = CGPoint(x: -d.y / len, y: d.x / len)
                let w = (base + (tip - base) * CGFloat(i) / CGFloat(pts.count - 1)) / 2
                out.append(CGPoint(x: p.x + n.x * w * sign, y: p.y + n.y * w * sign))
            }
            return out
        }
        let top = side(1), bottom = side(-1)
        let limb = CGMutablePath()
        limb.move(to: bottom[0])
        limb.addLine(to: top[0])
        limb.addQuadCurve(to: top[2], control: top[1])
        limb.addArc(center: pts[2], radius: tip / 2, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        limb.addQuadCurve(to: bottom[0], control: bottom[1])
        limb.closeSubpath()
        return limb
    }

    /// Where the twigs come off a branch, and where each ends.
    static func branchTwigs(_ r: CGRect, _ s: Int) -> [(from: CGPoint, to: CGPoint)] {
        let pts = branchLine(r).map(\.point)
        return (0..<4).map { k in
            let t = 0.3 + CGFloat(k) * 0.17
            let bx = pts[0].x + (pts[2].x - pts[0].x) * t, by = pts[0].y + (pts[2].y - pts[0].y) * t + r.height * 0.04
            let dir = CGPoint(x: 0.35 + (rnd(s, k) - 0.5) * 0.6, y: 1)
            let len = r.height * (0.2 + rnd(s + 1, k) * 0.15)
            return (CGPoint(x: bx, y: by), CGPoint(x: bx + dir.x * len, y: by + dir.y * len))
        }
    }

    /// A bleached trunk lying on its side, and the stub of a branch
    /// sticking up from it.
    static func driftwood(_ r: CGRect, _ s: Int, u: CGFloat) -> (body: CGPath, stub: CGPath) {
        let body = CGMutablePath()
        let h = r.height * 0.6
        body.move(to: CGPoint(x: r.minX + r.width * 0.03, y: r.minY + h * 0.12))
        // The root end: a couple of knuckles.
        body.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.55), control: CGPoint(x: r.minX - r.width * 0.02, y: r.minY + h * 0.3))
        body.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + h * 0.98), control: CGPoint(x: r.minX - r.width * 0.01, y: r.minY + h * 0.85))
        body.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.14, y: r.minY + h * 0.92), control: CGPoint(x: r.minX + r.width * 0.1, y: r.minY + h * 1.08))
        // Along the top to the tip.
        body.addCurve(to: CGPoint(x: r.maxX - r.width * 0.02, y: r.minY + h * 0.5),
                      control1: CGPoint(x: r.minX + r.width * 0.45, y: r.minY + h * 0.95), control2: CGPoint(x: r.minX + r.width * 0.75, y: r.minY + h * 0.62))
        // A splintered end.
        body.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.4))
        body.addLine(to: CGPoint(x: r.maxX - r.width * 0.03, y: r.minY + h * 0.33))
        body.addLine(to: CGPoint(x: r.maxX - r.width * 0.01, y: r.minY + h * 0.24))
        body.addCurve(to: CGPoint(x: r.minX + r.width * 0.03, y: r.minY + h * 0.12),
                      control1: CGPoint(x: r.minX + r.width * 0.7, y: r.minY + h * 0.05), control2: CGPoint(x: r.minX + r.width * 0.3, y: r.minY - h * 0.04))
        body.closeSubpath()
        let stub = CGMutablePath()
        let sx = r.minX + r.width * (0.3 + rnd(s, 1) * 0.2)
        stub.move(to: CGPoint(x: sx, y: r.minY + h * 0.7))
        stub.addLine(to: CGPoint(x: sx - r.width * 0.06, y: r.maxY))
        stub.addLine(to: CGPoint(x: sx - r.width * 0.02, y: r.maxY - 2 * u))
        stub.addLine(to: CGPoint(x: sx + r.width * 0.05, y: r.minY + h * 0.75))
        stub.closeSubpath()
        return (body, stub)
    }

    /// A slab of cork bark, stood on end, rounded over at the top.
    static func barkSlab(_ r: CGRect) -> CGPath {
        let slab = CGMutablePath()
        slab.move(to: CGPoint(x: r.minX, y: r.minY))
        slab.addLine(to: CGPoint(x: r.minX + r.width * 0.04, y: r.maxY - r.width * 0.3))
        slab.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.maxY - r.width * 0.12), control: CGPoint(x: r.midX, y: r.maxY + r.width * 0.05))
        slab.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        slab.closeSubpath()
        return slab
    }

    // MARK: Stone

    static func rockPath(_ r: CGRect, _ s: Int) -> CGPath {
        let n = 9
        var pts: [CGPoint] = []
        for k in 0..<n {
            let a = CGFloat(k) / CGFloat(n) * 2 * .pi + 0.2
            let rad = 1 - rnd(s, k) * 0.16
            // A flat-bottomed stone: the lower half squashed onto the ground.
            pts.append(CGPoint(x: r.midX + cos(a) * r.width / 2 * rad,
                               y: r.minY + r.height * 0.3 + sin(a) * r.height * (sin(a) < 0 ? 0.3 : 0.7) * rad))
        }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
        for k in 0..<n {
            let nx = pts[(k + 1) % n]
            p.addQuadCurve(to: CGPoint(x: (pts[k].x + nx.x) / 2, y: (pts[k].y + nx.y) / 2), control: pts[k])
        }
        p.closeSubpath()
        return p
    }

    // MARK: Plants

    /// Bamboo's three stalks, each a rounded rectangle.
    static func bambooStalks(_ r: CGRect, _ s: Int) -> [(rect: CGRect, radius: CGFloat)] {
        (0..<3).map { k in
            let w = r.width * 0.2
            let x = r.minX + r.width * (0.2 + CGFloat(k) * 0.3) - w / 2
            let h = r.height * (k == 1 ? 1 : 0.7 + rnd(s, k) * 0.2)
            return (CGRect(x: x, y: r.minY, width: w, height: h), w * 0.3)
        }
    }

    /// A cactus's trunk, and its two arms (the elbow and the upright of
    /// each), as rounded rectangles.
    static func cactus(_ r: CGRect) -> (trunk: CGPath, arms: [(rect: CGRect, radius: CGFloat)]) {
        let w = r.width * 0.4
        let trunk = CGPath(roundedRect: CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height * 0.97), cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
        var arms: [(CGRect, CGFloat)] = []
        for (side, lift, len) in [(CGFloat(-1), CGFloat(0.35), CGFloat(0.35)), (1, 0.5, 0.3)] {
            let aw = w * 0.62
            let elbowX = side > 0 ? r.midX + w * 0.3 : r.midX - w * 0.3
            let outX = side > 0 ? r.midX + w / 2 + aw * 0.55 : r.midX - w / 2 - aw * 0.55
            let y = r.minY + r.height * lift
            arms.append((CGRect(x: min(elbowX, outX) - aw * 0.1, y: y, width: abs(outX - elbowX) + aw * 0.5, height: aw), aw / 2))
            arms.append((CGRect(x: outX - aw / 2, y: y, width: aw, height: r.height * len + aw), aw / 2))
        }
        return (trunk, arms)
    }

    /// A leafy plant's pot and the rim round its top.
    static func plantPot(_ r: CGRect, u: CGFloat) -> (pot: CGPath, rim: CGPath) {
        let pot = CGMutablePath()
        let pw = r.width * 0.4, ph = r.height * 0.2
        pot.move(to: CGPoint(x: r.midX - pw * 0.4, y: r.minY))
        pot.addLine(to: CGPoint(x: r.midX + pw * 0.4, y: r.minY))
        pot.addLine(to: CGPoint(x: r.midX + pw * 0.5, y: r.minY + ph * 0.8))
        pot.addLine(to: CGPoint(x: r.midX - pw * 0.5, y: r.minY + ph * 0.8))
        pot.closeSubpath()
        let rim = CGPath(roundedRect: CGRect(x: r.midX - pw * 0.56, y: r.minY + ph * 0.76, width: pw * 1.12, height: ph * 0.28), cornerWidth: 2 * u, cornerHeight: 2 * u, transform: nil)
        return (pot, rim)
    }

    /// A leafy plant's stems: each from the pot, through its bend, to its
    /// tip, and the big leaf there (its size and which way it points).
    static func plantStems(_ r: CGRect, _ s: Int) -> [(base: CGPoint, control: CGPoint, tip: CGPoint, leaf: CGFloat, angle: CGFloat)] {
        let stemBase = CGPoint(x: r.midX, y: r.minY + r.height * 0.2)
        return (0..<7).map { k in
            let a = CGFloat(k - 3) * 0.3 + (rnd(s, k) - 0.5) * 0.15
            let len = r.height * (0.45 + rnd(s + 1, k) * 0.25)
            let tip = CGPoint(x: stemBase.x + sin(a) * len * 0.9, y: stemBase.y + cos(a) * len)
            return (stemBase, CGPoint(x: stemBase.x + sin(a) * len * 0.2, y: stemBase.y + len * 0.7), tip,
                    r.width * (0.26 + rnd(s + 2, k) * 0.08), .pi / 2 - a * 1.4)
        }
    }

    /// The broad leaves on top of a leafy plant, lying flat: where each is,
    /// and how big.
    static func plantPads(_ r: CGRect) -> [(at: CGPoint, size: CGFloat, angle: CGFloat)] {
        (0..<3).map { k -> (at: CGPoint, size: CGFloat, angle: CGFloat) in
            let f = CGFloat(k)
            let at = CGPoint(x: r.minX + r.width * (0.3 + f * 0.2), y: r.maxY - r.height * 0.16)
            let angle: CGFloat = (f - 1) * 0.35 + .pi / 2 - 0.1
            return (at, r.width * 0.3, angle)
        }
    }

    /// A big leaf, `l` long, in its own frame (its stalk at the origin);
    /// flat, it lies across instead of standing up.
    static func bigLeaf(_ l: CGFloat, flat: Bool) -> (path: CGPath, w: CGFloat, h: CGFloat) {
        let w = flat ? l * 0.9 : l * 0.62, h = flat ? l * 0.34 : l
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: 0, y: flat ? 0 : -h * 0.1))
        if flat {
            leaf.addEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        } else {
            leaf.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: -w * 0.8, y: h * 0.2), control2: CGPoint(x: -w * 0.5, y: h * 0.9))
            leaf.addCurve(to: CGPoint(x: 0, y: -h * 0.1), control1: CGPoint(x: w * 0.5, y: h * 0.9), control2: CGPoint(x: w * 0.8, y: h * 0.2))
        }
        return (leaf, w, h)
    }

    /// A hanging vine's two strands, twisted round each other: from the
    /// lid, through two bends, down to its end, and how thick each is.
    static func vineStrands(_ r: CGRect, u: CGFloat) -> [(from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint, width: CGFloat)] {
        [(3.2 * u, -2 * u), (2.6 * u, 2 * u)].map { w, off in
            (CGPoint(x: r.midX + off, y: r.maxY), CGPoint(x: r.midX + off * 4, y: r.maxY - r.height * 0.33),
             CGPoint(x: r.midX - off * 4, y: r.maxY - r.height * 0.66), CGPoint(x: r.midX - off, y: r.minY), w)
        }
    }

    /// Where a vine's leaves are: at each, which way it points and how big.
    static func vineLeaves(_ r: CGRect, _ s: Int, u: CGFloat) -> [(at: CGPoint, size: CGFloat, angle: CGFloat)] {
        let n = max(3, Int(r.height / (18 * u)))
        return (0..<n).map { k in
            let t = (CGFloat(k) + 0.5) / CGFloat(n)
            let y = r.maxY - t * r.height
            let side: CGFloat = k % 2 == 0 ? 1 : -1
            let x = r.midX + side * 2 * u + sin(t * 6) * 3 * u
            return (CGPoint(x: x, y: y), (11 + rnd(s, k) * 5) * u * (1 - t * 0.3),
                    side > 0 ? -0.5 - rnd(s + 1, k) * 0.4 : .pi + 0.5 + rnd(s + 1, k) * 0.4)
        }
    }

    // MARK: Water

    /// A water dish: the front of its bowl, and its rim seen from above.
    static func dish(_ r: CGRect) -> (front: CGPath, rim: CGRect) {
        let front = CGMutablePath()
        front.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.6))
        front.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.6))
        front.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        front.addLine(to: CGPoint(x: r.minX + r.width * 0.1, y: r.minY))
        front.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.6), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.1))
        front.closeSubpath()
        return (front, CGRect(x: r.minX, y: r.minY + r.height * 0.34, width: r.width, height: r.height * 0.56))
    }
}

// MARK: - Each kind's shape

extension HabitatShape {
    private static func bulk(_ name: String, _ path: CGPath) -> [ShapePart] {
        Poly.outlines(path).map { ShapePart(name: name, role: .bulk, outline: $0) }
    }
    private static func limb(_ name: String, _ path: CGPath) -> [ShapePart] {
        Poly.outlines(path).map { ShapePart(name: name, role: .limb, outline: $0) }
    }
    private static func roundRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        let k = min(radius, r.width / 2, r.height / 2)
        return CGPath(roundedRect: r, cornerWidth: k, cornerHeight: k, transform: nil)
    }
    /// The highest point of some parts, and the anchor on it.
    private static func perchOnTop(_ parts: [ShapePart], near x: CGFloat? = nil) -> ObjectAnchor? {
        var best: V2?
        for p in parts {
            for q in p.outline where x.map({ abs(q.x - $0) < 12 }) ?? true {
                if best == nil || q.y > best!.y { best = q }
            }
        }
        return best.map { ObjectAnchor(kind: .perch, point: $0, normal: V2(0, 1)) }
    }
    /// The lowest point of some parts near `x`: an underside to tie to.
    private static func tieUnder(_ parts: [ShapePart], near x: CGFloat) -> ObjectAnchor? {
        var best: V2?
        for p in parts {
            let o = p.outline
            for i in o.indices {
                let a = o[i], b = o[(i + 1) % o.count]
                // Undersides run right to left (clockwise, solid above).
                guard b.x < a.x, x >= b.x, x <= a.x else { continue }
                let y = a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
                if best == nil || y < best!.y { best = V2(x, y) }
            }
        }
        return best.map { ObjectAnchor(kind: .tie, point: $0, normal: V2(0, -1)) }
    }
    private static func circle(_ c: CGPoint, _ r: CGFloat) -> [V2] {
        Poly.outlines(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)).first ?? []
    }

    static func log(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        g.parts = bulk("body", logBody(r))
        if let p = perchOnTop(g.parts, near: r.midX) { g.anchors.append(p) }
        return g
    }

    static func hollowLog(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = log(r, s, u)
        // The dark hole at its left end runs on into the log, as far as the
        // cut face at the other end.
        let (_, inside) = logHole(r, u: u)
        let back = r.maxX - r.height * 0.46
        let cave = CGRect(x: inside.midX, y: inside.minY, width: max(back - inside.midX, 4), height: inside.height)
        g.hollows = [Hollow(cavity: Poly.outlines(roundRect(cave, inside.height / 2)).first ?? [],
                            mouth: V2(inside.midX, inside.minY), inward: V2(1, 0))]
        g.anchors.append(ObjectAnchor(kind: .entrance, point: V2(inside.midX, inside.minY), normal: V2(-1, 0)))
        return g
    }

    static func branch(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        g.parts = limb("limb", branchLimb(r, u: u))
        // The twigs and their leaves: to look at.
        g.visual = branchTwigs(r, s).map { circle($0.to, 12 * u) }
        let line = branchLine(r)
        if let t = tieUnder(g.parts, near: line[1].x) { g.anchors.append(t) }
        if let t = tieUnder(g.parts, near: line[2].x - r.width * 0.08) { g.anchors.append(t) }
        return g
    }

    static func driftwood(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        let (body, stub) = driftwood(r, s, u: u)
        g.parts = bulk("body", body) + limb("stub", stub)
        if let p = perchOnTop(g.parts.filter { $0.name == "body" }, near: r.minX + r.width * 0.3) { g.anchors.append(p) }
        return g
    }

    static func corkBark(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        g.parts = bulk("slab", barkSlab(r))
        if let p = perchOnTop(g.parts) { g.anchors.append(p) }
        return g
    }

    static func rock(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        g.parts = bulk("stone", rockPath(r, s))
        if let p = perchOnTop(g.parts) { g.anchors.append(p) }
        return g
    }

    static func bamboo(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        for st in bambooStalks(r, s) {
            g.parts += limb("stalk", roundRect(st.rect, st.radius))
            // Its crown of leaves.
            g.visual.append(circle(CGPoint(x: st.rect.midX + 10 * u, y: st.rect.maxY + 8 * u), 22 * u))
        }
        return g
    }

    static func cactus(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        let (trunk, arms) = cactus(r)
        g.parts = bulk("trunk", trunk) + arms.flatMap { limb("arm", roundRect($0.rect, $0.radius)) }
        if let p = perchOnTop(g.parts.filter { $0.name == "trunk" }) { g.anchors.append(p) }
        if rnd(s, 30) < 0.6 { g.visual.append(circle(CGPoint(x: r.midX, y: r.minY + r.height * 0.97 + 2 * u), 6 * u)) }
        return g
    }

    static func plant(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        let (pot, rim) = plantPot(r, u: u)
        g.parts = bulk("pot", pot) + bulk("rim", rim)
        // The stems, and the big leaf at the end of each: what holds the
        // plant up, and what it can climb.
        for st in plantStems(r, s) {
            let line = (0...10).map { k -> V2 in
                let t = CGFloat(k) / 10
                let a = V2(st.base), c = V2(st.control), b = V2(st.tip)
                return a * ((1 - t) * (1 - t)) + c * (2 * t * (1 - t)) + b * (t * t)
            }
            g.parts.append(ShapePart(name: "stem", role: .limb, outline: Poly.limb(line, halfWidth: max(1.2 * u, 1))))
            let leaf = bigLeaf(st.leaf, flat: false)
            var t = CGAffineTransform(translationX: st.tip.x, y: st.tip.y).rotated(by: st.angle - .pi / 2)
            if let p = leaf.path.copy(using: &t) { g.parts += limb("leaf", p) }
        }
        // The broad leaves lying flat on top.
        for pad in plantPads(r) {
            let leaf = bigLeaf(pad.size, flat: true)
            var t = CGAffineTransform(translationX: pad.at.x, y: pad.at.y)
            if let p = leaf.path.copy(using: &t) { g.parts += limb("pad", p) }
        }
        let pads = g.parts.filter { $0.name == "pad" }
        if let p = perchOnTop(pads, near: r.midX) { g.anchors.append(p) }
        if let t = tieUnder(pads, near: r.midX) { g.anchors.append(t) }
        return g
    }

    static func vine(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        // The two strands twist round each other: together, one band.
        let strands = vineStrands(r, u: u)
        func at(_ st: (from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint, width: CGFloat), _ t: CGFloat) -> V2 {
            let m = 1 - t
            return V2(st.from) * (m * m * m) + V2(st.c1) * (3 * m * m * t) + V2(st.c2) * (3 * m * t * t) + V2(st.to) * (t * t * t)
        }
        let n = max(8, Int(r.height / 14))
        var left: [V2] = [], right: [V2] = []
        for k in 0...n {
            let t = CGFloat(k) / CGFloat(n)
            var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude, y: CGFloat = 0
            for st in strands {
                let p = at(st, t)
                lo = min(lo, p.x - st.width / 2)
                hi = max(hi, p.x + st.width / 2)
                y = p.y
            }
            left.append(V2(lo, y))
            right.append(V2(hi, y))
        }
        // Down the left, round the end, up the right.
        let end = V2((left[n].x + right[n].x) / 2, r.minY - 1.5 * u)
        g.parts = [ShapePart(name: "strand", role: .limb, outline: Poly.clockwise(left + [end] + right.reversed()))]
        g.visual = vineLeaves(r, s, u: u).map { leaf in
            circle(CGPoint(x: leaf.at.x + cos(leaf.angle) * leaf.size * 0.5, y: leaf.at.y + sin(leaf.angle) * leaf.size * 0.5), leaf.size * 0.42)
        }
        g.anchors.append(ObjectAnchor(kind: .tie, point: V2(r.midX, r.maxY), normal: V2(0, -1)))
        return g
    }

    static func waterDish(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        let (front, rim) = dish(r)
        g.parts = bulk("bowl", front) + bulk("rim", CGPath(ellipseIn: rim, transform: nil))
        g.anchors.append(ObjectAnchor(kind: .perch, point: V2(rim.midX, rim.maxY), normal: V2(0, 1)))
        return g
    }

    // Scenery: nothing to stand on — only where it is drawn, roughly.

    static func fern(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var pts: [V2] = [V2(r.midX, r.minY)]
        for k in 0..<8 {
            let a = CGFloat(k) / 7 * 2.4 - 1.2 + (rnd(s, k) - 0.5) * 0.2
            let len = r.height * (0.75 + rnd(s + 1, k) * 0.3)
            pts.append(V2(r.midX + sin(a) * len * 1.15, r.minY + cos(a) * len * 0.95))
            pts.append(V2(r.midX + sin(a) * len * 0.35, r.minY + len * 0.95))
        }
        return ObjectGeometry(visual: [Poly.hull(pts)])
    }

    static func grass(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var pts: [V2] = []
        for k in 0..<18 {
            let x = r.minX + r.width * (0.25 + rnd(s, k) * 0.5)
            let h = r.height * (0.5 + rnd(s + 1, k) * 0.5)
            let lean = (rnd(s + 2, k) - 0.5) * r.width * 0.9
            let w = (2 + rnd(s + 3, k) * 2.5) * u
            pts += [V2(x - w, r.minY), V2(x + w, r.minY), V2(x + lean, r.minY + h)]
        }
        return ObjectGeometry(visual: [Poly.hull(pts)])
    }

    static func flowers(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var pts: [V2] = []
        for k in 0..<5 {
            let x = r.minX + r.width * (0.14 + CGFloat(k) * 0.18) + (rnd(s, k) - 0.5) * 8 * u
            let h = r.height * (0.55 + rnd(s + 1, k) * 0.4)
            let lean = (rnd(s + 2, k) - 0.5) * 8 * u
            let pr = (4.5 + rnd(s + 3, k) * 2) * u * 1.6
            pts += [V2(x, r.minY), V2(x + lean - pr, r.minY + h), V2(x + lean + pr, r.minY + h), V2(x + lean, r.minY + h + pr)]
        }
        return ObjectGeometry(visual: [Poly.hull(pts)])
    }

    static func succulent(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        let c0 = V2(r.midX, r.minY + r.height * 0.25)
        var pts: [V2] = [V2(r.midX - r.width * 0.1, r.minY), V2(r.midX + r.width * 0.1, r.minY)]
        for ring in 0..<3 {
            let n = 7 - ring
            let len = r.width * (0.5 - CGFloat(ring) * 0.12)
            for k in 0..<n {
                let a = .pi / 2 + (CGFloat(k) - CGFloat(n - 1) / 2) * (2.4 / CGFloat(n)) + CGFloat(ring) * 0.2
                pts.append(c0 + V2(cos(a) * len, sin(a) * len * 0.75))
            }
        }
        return ObjectGeometry(visual: [Poly.hull(pts)])
    }

    static func mushrooms(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var g = ObjectGeometry()
        for k in 0..<3 {
            let x = r.minX + r.width * (0.2 + CGFloat(k) * 0.3) + (rnd(s, k) - 0.5) * 6 * u
            let h = r.height * (0.55 + rnd(s + 1, k) * 0.45)
            let cw = r.width * (0.26 + rnd(s + 2, k) * 0.12)
            g.visual.append(Poly.hull([V2(x - cw * 0.14, r.minY), V2(x + cw * 0.14, r.minY), V2(x - cw / 2, r.minY + h * 0.58),
                                       V2(x + cw / 2, r.minY + h * 0.58), V2(x - cw * 0.3, r.minY + h * 0.95), V2(x + cw * 0.3, r.minY + h * 0.95)]))
        }
        return g
    }

    static func groundCover(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        ObjectGeometry(visual: [Poly.outlines(roundRect(r, r.height * 0.45)).first ?? []])
    }

    static func crystals(_ r: CGRect, _ s: Int, _ u: CGFloat) -> ObjectGeometry {
        var pts: [V2] = [V2(r.minX + r.width * 0.1, r.minY), V2(r.maxX - r.width * 0.1, r.minY)]
        let n = 5
        for k in 0..<n {
            let a = (CGFloat(k) - CGFloat(n - 1) / 2) * 0.3 + (rnd(s, k) - 0.5) * 0.15
            let len = r.height * (k == n / 2 ? 0.95 : 0.5 + rnd(s + 1, k) * 0.3)
            let base = V2(r.midX + (CGFloat(k) - CGFloat(n - 1) / 2) * r.width * 0.12, r.minY + r.height * 0.08)
            pts.append(base + V2(0, len).rotated(by: -a))
        }
        return ObjectGeometry(visual: [Poly.hull(pts)])
    }
}

// MARK: - Polygons

enum Poly {
    /// The closed outlines a path draws, flattened into polygons (curves
    /// cut into pieces a few points long), clockwise, lightly simplified.
    static func outlines(_ path: CGPath, step: CGFloat = 5) -> [[V2]] {
        var subs: [[V2]] = []
        var cur: [V2] = []
        var last = V2.zero
        func close() {
            if let f = cur.first, let l = cur.last, cur.count > 1, f.distance(to: l) < 0.01 { cur.removeLast() }
            if cur.count >= 3 { subs.append(cur) }
            cur = []
        }
        path.applyWithBlock { e in
            let el = e.pointee
            switch el.type {
            case .moveToPoint:
                close()
                last = V2(el.points[0])
                cur = [last]
            case .addLineToPoint:
                last = V2(el.points[0])
                cur.append(last)
            case .addQuadCurveToPoint:
                let c = V2(el.points[0]), p = V2(el.points[1])
                let n = max(2, min(24, Int(((c - last).length + (p - c).length) / step)))
                for k in 1...n {
                    let t = CGFloat(k) / CGFloat(n), m = 1 - t
                    cur.append(last * (m * m) + c * (2 * m * t) + p * (t * t))
                }
                last = p
            case .addCurveToPoint:
                let c1 = V2(el.points[0]), c2 = V2(el.points[1]), p = V2(el.points[2])
                let n = max(2, min(32, Int(((c1 - last).length + (c2 - c1).length + (p - c2).length) / step)))
                for k in 1...n {
                    let t = CGFloat(k) / CGFloat(n), m = 1 - t
                    cur.append(last * (m * m * m) + c1 * (3 * m * m * t) + c2 * (3 * m * t * t) + p * (t * t * t))
                }
                last = p
            case .closeSubpath:
                if let f = cur.first { last = f }
                close()
            @unknown default:
                break
            }
        }
        close()
        return subs.map { clockwise(simplify(dedupe($0), tolerance: 0.3)) }.filter { $0.count >= 3 && abs(area($0)) > 1 }
    }

    /// Consecutive points that are all but the same, dropped.
    static func dedupe(_ pts: [V2], within d: CGFloat = 0.05) -> [V2] {
        var out: [V2] = []
        for p in pts where out.last.map({ $0.distance(to: p) > d }) ?? true { out.append(p) }
        while out.count > 2, out[0].distance(to: out[out.count - 1]) <= d { out.removeLast() }
        return out
    }

    /// Signed area: negative going clockwise (y up).
    static func area(_ pts: [V2]) -> CGFloat {
        var s: CGFloat = 0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    static func clockwise(_ pts: [V2]) -> [V2] { area(pts) > 0 ? pts.reversed() : pts }

    static func bounds(_ pts: [V2]) -> CGRect {
        guard let f = pts.first else { return .null }
        var x0 = f.x, x1 = f.x, y0 = f.y, y1 = f.y
        for p in pts { x0 = min(x0, p.x); x1 = max(x1, p.x); y0 = min(y0, p.y); y1 = max(y1, p.y) }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// A closed polygon with points that add nothing (within `tolerance`
    /// of the line past them) left out.
    static func simplify(_ pts: [V2], tolerance: CGFloat) -> [V2] {
        guard pts.count > 4 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        // Split at the point furthest from the first.
        var far = 0
        for i in pts.indices where pts[i].distance(to: pts[0]) > pts[far].distance(to: pts[0]) { far = i }
        func dp(_ i: Int, _ j: Int) {
            guard j > i + 1 else { return }
            var worst = -1
            var wd = tolerance
            for k in (i + 1)..<j {
                let d = projectOnSegment(pts[k], pts[i], pts[j % pts.count]).dist
                if d > wd { wd = d; worst = k }
            }
            guard worst >= 0 else { return }
            keep[worst] = true
            dp(i, worst)
            dp(worst, j)
        }
        keep[0] = true
        keep[far] = true
        dp(0, far)
        dp(far, pts.count)
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    /// A polygon cut down to what lies within a rect.
    static func clip(_ poly: [V2], to r: CGRect) -> [V2] {
        guard !r.contains(bounds(poly)) else { return poly }
        var out = poly
        let edges: [(V2) -> CGFloat] = [{ $0.x - r.minX }, { r.maxX - $0.x }, { $0.y - r.minY }, { r.maxY - $0.y }]
        for inside in edges {
            let input = out
            out = []
            guard !input.isEmpty else { break }
            for i in input.indices {
                let a = input[i], b = input[(i + 1) % input.count]
                let da = inside(a), db = inside(b)
                if da >= 0 { out.append(a) }
                if (da >= 0) != (db >= 0) { out.append(a + (b - a) * (da / (da - db))) }
            }
        }
        return dedupe(out)
    }

    /// Whether `p` is inside a closed polygon.
    static func contains(_ poly: [V2], _ p: V2) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Whether a closed path goes round `p` (any number of times, either
    /// way): inside it, even where it crosses itself.
    static func winds(_ poly: [V2], _ p: V2) -> Bool {
        var w = 0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            if a.y <= p.y {
                if b.y > p.y, (b - a).cross(p - a) > 0 { w += 1 }
            } else if b.y <= p.y, (b - a).cross(p - a) < 0 {
                w -= 1
            }
        }
        return w != 0
    }

    /// How far `p` is from a closed polygon's outline.
    static func distance(_ poly: [V2], _ p: V2) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for i in poly.indices { best = min(best, projectOnSegment(p, poly[i], poly[(i + 1) % poly.count]).dist) }
        return best
    }

    /// The outline round a line (a stem, say) `halfWidth` either side of
    /// it, with rounded ends.
    static func limb(_ line: [V2], halfWidth w: CGFloat) -> [V2] {
        guard line.count >= 2 else { return [] }
        var left: [V2] = [], right: [V2] = []
        for i in line.indices {
            let a = line[max(i - 1, 0)], b = line[min(i + 1, line.count - 1)]
            let d = (b - a).normalized
            let n = V2(-d.y, d.x)
            left.append(line[i] + n * w)
            right.append(line[i] - n * w)
        }
        func cap(_ c: V2, from d: V2) -> [V2] {
            // Half way round from one side to the other, over the end.
            (1...3).map { k in c + d.rotated(by: -CGFloat(k) / 4 * .pi) * w }
        }
        let d0 = (line[1] - line[0]).normalized, d1 = (line[line.count - 1] - line[line.count - 2]).normalized
        let endCap = cap(line[line.count - 1], from: V2(-d1.y, d1.x))
        let startCap = cap(line[0], from: V2(d0.y, -d0.x))
        return clockwise(left + endCap + right.reversed() + startCap)
    }

    /// The smallest convex polygon round some points.
    static func hull(_ pts: [V2]) -> [V2] {
        let s = pts.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard s.count > 2 else { return s }
        func half(_ ps: [V2]) -> [V2] {
            var h: [V2] = []
            for p in ps {
                while h.count >= 2, (h[h.count - 1] - h[h.count - 2]).cross(p - h[h.count - 2]) <= 0 { h.removeLast() }
                h.append(p)
            }
            return h
        }
        let lower = half(s), upper = half(s.reversed())
        return clockwise(Array(lower.dropLast()) + Array(upper.dropLast()))
    }

    /// A closed clockwise polygon grown outward by `g`: each side moved out,
    /// convex corners rounded, concave ones mitred where there is room.
    /// Where the outline turns in on itself tighter than `g` the result
    /// crosses itself; the surfaces trim that off (see `SurfaceTrace`).
    static func grown(_ poly: [V2], by g: CGFloat) -> [V2] {
        let pts = dedupe(poly)
        let n = pts.count
        guard n >= 3 else { return pts }
        var out: [V2] = []
        for i in 0..<n {
            let p = pts[i], prev = pts[(i - 1 + n) % n], next = pts[(i + 1) % n]
            let d0 = (p - prev).normalized, d1 = (next - p).normalized
            let n0 = V2(-d0.y, d0.x), n1 = V2(-d1.y, d1.x)
            let turn = d0.cross(d1)
            let cosT = clamp(d0.dot(d1), -1, 1)
            let angle = acos(cosT)
            if angle < 0.02 {
                out.append(p + (n0 + n1).normalized * g)
            } else if turn < 0 {
                // Convex: round it.
                // (Steps of at most 0.4 radians: the middle of each is
                // within 2% of `g` of the corner — see `SurfaceTrace`.)
                let steps = max(1, Int(ceil(angle / 0.4)))
                for k in 0...steps {
                    out.append(p + n0.rotated(by: -angle * CGFloat(k) / CGFloat(steps)) * g)
                }
            } else {
                // Concave: the two sides meet, if the corner has room for it.
                let back = g * tan(angle / 2)
                if back < 0.95 * min(p.distance(to: prev), p.distance(to: next)) {
                    out.append(p + (n0 + n1) * (g / (1 + n0.dot(n1))))
                } else {
                    out.append(p + n0 * g)
                    out.append(p + n1 * g)
                }
            }
        }
        return dedupe(out)
    }
}

// MARK: - Surfaces

/// A habitat's surfaces: the map's loops, and the junctions between them.
struct HabitatSurfaces {
    /// The open space of the tank (its "screen").
    var air: CGRect
    var loops: [SurfaceLoop]
    var junctions: [SurfaceJunction]
}

extension Habitat {
    /// Everything it can walk on, in world points — offset by `origin`
    /// (the tools lay a world out somewhere on a mock desktop): round the
    /// inside of the tank — along the ground, up the glass, across under
    /// the lid and back down — and round everything in it, following the
    /// shapes of things (see the top of HabitatGeometry.swift). Built once
    /// for the layout: the camera moving about the world changes none of it.
    func surfaces(at origin: CGPoint = .zero, standoff off: CGFloat) -> HabitatSurfaces {
        let scene = CGRect(origin: origin, size: size)
        let groundY = scene.minY + HabitatLayout.ground
        let air = CGRect(x: scene.minX, y: groundY, width: scene.width, height: scene.maxY - groundY)
        guard air.width > 2 * off + 40, air.height > 2 * off + 40 else { return HabitatSurfaces(air: air, loops: [], junctions: []) }
        var parts: [SurfaceTrace.Part] = []
        for (i, it) in items.enumerated() where it.kind.climbable {
            var g = it.geometry
            if origin != .zero { g = g.mapped { V2($0.x + origin.x, $0.y + origin.y) } }
            for part in g.parts where part.outline.count >= 3 {
                parts.append(SurfaceTrace.Part(outline: part.outline, role: part.role, group: it.id, owner: it.id,
                                               depth: items.count - i, rect: it.rect.offsetBy(dx: origin.x, dy: origin.y)))
            }
        }
        return SurfaceTrace.build(parts: parts, air: air, standoff: off)
    }

    /// The top of whatever of it there is to rest something on, between
    /// `lo` and `hi` across (world points), if any.
    static func restingTop(_ it: HabitatItem, from lo: CGFloat, to hi: CGFloat) -> CGFloat? {
        guard it.kind.climbable else { return nil }
        return it.geometry.top(from: lo, to: hi)
    }
}

/// Turns outlines into the map's loops. Every outline is grown by the height
/// of the body (the line the body's middle follows); every crossing of two
/// of those lines is found; the stretches of each that lie within something
/// that swallows them are dropped (bulk swallows anything, limbs swallow the
/// other limbs of the same thing, and the tank everything beyond the ground,
/// the glass and the lid); what is left is joined up, following one line
/// where it goes on and turning onto the other where it does not — which is
/// how bulk runs together with whatever it touches — into loops and runs.
/// Where two of those meet without running on into each other is a junction.
/// The feet's edges are found the same way from the outlines themselves.
enum SurfaceTrace {
    struct Part {
        var outline: [V2]
        var role: ShapePart.Role
        /// Limbs of one group join up (one thing's own).
        var group: Int
        /// The thing it belongs to (0: the tank).
        var owner: Int
        var depth: Int
        var rect: CGRect
        var rim = false
        fileprivate var box: CGRect = .null

        init(outline: [V2], role: ShapePart.Role, group: Int, owner: Int, depth: Int, rect: CGRect, rim: Bool = false) {
            self.outline = outline
            self.role = role
            self.group = group
            self.owner = owner
            self.depth = depth
            self.rect = rect
            self.rim = rim
            box = Poly.bounds(outline)
        }
    }

    struct Chain {
        var pts: [V2]
        /// Per piece (pts.count - 1 of them, or pts.count if closed).
        var parts: [Int]
        var vertexIDs: [Int]
        var closed: Bool
        var pieceCount: Int { closed ? pts.count : pts.count - 1 }
    }

    static func build(parts given: [Part], air: CGRect, standoff off: CGFloat) -> HabitatSurfaces {
        // The tank itself: its path is the inside of the glass, the ground
        // and the lid, going round with the tank on the right.
        func rimPath(_ r: CGRect) -> [V2] { [V2(r.minX, r.minY), V2(r.maxX, r.minY), V2(r.maxX, r.maxY), V2(r.minX, r.maxY)] }
        var parts = given
        parts.append(Part(outline: rimPath(air), role: .bulk, group: 0, owner: 0, depth: 1_000_000, rect: air, rim: true))
        let rim = parts.count - 1
        // (A hair off the round numbers the ground and the glass are at, so
        // that nothing lies exactly along them.)
        let inner = air.insetBy(dx: off + 0.013, dy: off + 0.013)
        let bodyPaths = parts.indices.map { $0 == rim ? rimPath(inner) : Poly.grown(parts[$0].outline, by: off) }
        var body = trace(parts: parts, paths: bodyPaths, grow: off, free: air.insetBy(dx: off, dy: off))
        let edgeAir = air.insetBy(dx: -0.013, dy: -0.013)
        let edges = trace(parts: parts, paths: parts.indices.map { $0 == rim ? rimPath(edgeAir) : parts[$0].outline }, grow: 0, free: air)

        // The edges, by the parts they are the edges of (not by the thing:
        // a plant's pot is part of the ground's surface, its leaves are not).
        var edgeRuns: [[Seg]] = []
        var edgesOf: [Int: [Int]] = [:]
        for ch in edges.chains {
            let segs = segments(ch, parts: parts).segs
            guard !segs.isEmpty else { continue }
            for part in Set(ch.parts) { edgesOf[part, default: []].append(edgeRuns.count) }
            edgeRuns.append(segs)
        }

        tieLooseEnds(&body)
        // Where chains meet: each vertex, and every place along a chain it is.
        var meets: [Int: [(chain: Int, pos: Int)]] = [:]
        for (c, ch) in body.chains.enumerated() {
            let n = ch.closed ? ch.pts.count : ch.pts.count
            for pos in 0..<n { meets[ch.vertexIDs[pos], default: []].append((c, pos)) }
        }
        let junctionVertices = Set(meets.filter { $0.value.count > 1 }.keys)

        // The tank's own surface — round the glass, the lid and the ground
        // — is "screen:0": of the runs that take in part of it, the one that
        // reaches furthest (a room closed in under a bridge takes in a
        // stretch of the ground too).
        let mainRim = body.chains.indices.filter { body.chains[$0].parts.contains(rim) }
            .max { a, b in
                let ra = Poly.bounds(body.chains[a].pts), rb = Poly.bounds(body.chains[b].pts)
                return ra.width * ra.height < rb.width * rb.height
            }
        var loops: [SurfaceLoop] = []
        var loopOfChain: [Int: Int] = [:]
        var vertexMap: [Int: [Int: Int]] = [:]   // chain -> position -> loop vertex
        var used = Set<String>()
        for (c, ch) in body.chains.enumerated() {
            let built = segments(ch, parts: parts, keep: junctionVertices)
            // (A scrap of a surface is no surface; nor is the inside of a
            // gap between things too small for the spider to be in.)
            guard built.segs.reduce(0, { $0 + $1.len }) > 6 else { continue }
            if ch.closed, Poly.area(ch.pts) > 0, Poly.area(ch.pts) < .pi * 4 * off * off { continue }
            let owners = Set(ch.parts.map { parts[$0].owner })
            let onRim = ch.parts.contains(rim)
            var id = onRim ? (c == mainRim ? "screen:0" : "screen:0~r") : "item:\(owners.filter { $0 != 0 }.min() ?? 0)"
            if used.contains(id) {
                var k = 1
                while used.contains("\(id)~\(k)") { k += 1 }
                id = "\(id)~\(k)"
            }
            used.insert(id)
            let rect = onRim ? air : owners.reduce(CGRect.null) { r, o in
                parts.first { $0.owner == o }.map { r.union($0.rect) } ?? r
            }
            let depth = ch.parts.map { parts[$0].depth }.min() ?? 0
            var loop = SurfaceLoop(id: id, kind: onRim ? .screenBorder : .windowEdge, segs: built.segs,
                                   closed: ch.closed, depth: depth, rect: rect)
            loop.owners = built.owners
            let runs = Set(Set(ch.parts).flatMap { edgesOf[$0] ?? [] }).sorted()
            loop.edge = runs.flatMap { edgeRuns[$0] }
            loopOfChain[c] = loops.count
            vertexMap[c] = built.vertexAt
            loops.append(loop)
        }

        var junctions: [SurfaceJunction] = []
        for v in junctionVertices.sorted() {
            guard let at = meets[v] else { continue }
            for a in at {
                for b in at where !(a.chain == b.chain && a.pos == b.pos) {
                    guard let la = loopOfChain[a.chain], let lb = loopOfChain[b.chain],
                          let va = vertexMap[a.chain]?[a.pos], let vb = vertexMap[b.chain]?[b.pos] else { continue }
                    junctions.append(SurfaceJunction(from: loops[la].id, fromVertex: va, to: loops[lb].id, toVertex: vb, at: body.vertices[v]))
                }
            }
        }
        return HabitatSurfaces(air: air, loops: loops, junctions: junctions)
    }

    /// A chain's pieces as the map's segments: runs of pieces along one
    /// straight line joined into one, except where `keep` says a vertex
    /// must stay one (a junction) or the owner changes. `vertexAt` maps a
    /// chain position to the loop vertex it became.
    static func segments(_ ch: Chain, parts: [Part], keep: Set<Int> = []) -> (segs: [Seg], owners: [Int], vertexAt: [Int: Int]) {
        var segs: [Seg] = [], owners: [Int] = []
        var vertexAt: [Int: Int] = [:]
        let n = ch.pieceCount
        guard n > 0 else { return ([], [], [:]) }
        func facing(_ d: V2) -> EdgeFacing {
            let nrm = V2(-d.y, d.x)
            if abs(nrm.y) >= abs(nrm.x) { return nrm.y >= 0 ? .up : .down }
            return nrm.x >= 0 ? .right : .left
        }
        // The run being gathered into one segment, and the chain positions
        // that become its first vertex.
        var start = ch.pts[0], end = ch.pts[0]
        var pending = [0]
        var owner = parts[ch.parts[0]].owner
        func flush() {
            // (A run too short to be a segment goes on into the next.)
            guard end.distance(to: start) > 0.05 else { return }
            for p in pending { vertexAt[p] = segs.count }
            pending = []
            segs.append(Seg(start, end, facing((end - start).normalized)))
            owners.append(owner)
            start = end
        }
        for k in 0..<n {
            let a = ch.pts[k], b = ch.pts[(k + 1) % ch.pts.count]
            let o = parts[ch.parts[k]].owner
            if k > 0 {
                // Does this piece carry on along the run so far?
                let run = end - start
                let straight = run.length <= 0.05 || (b - a).length <= 0.05
                    || (abs(run.normalized.cross((b - a).normalized)) < 0.004 && run.dot(b - a) > 0)
                if !straight || keep.contains(ch.vertexIDs[k]) || o != owner {
                    flush()
                    pending.append(k)
                    owner = o
                }
            }
            end = b
        }
        flush()
        if !pending.isEmpty, let last = segs.last {
            // A last scrap too short to be a segment: the one before runs on over it.
            segs[segs.count - 1] = Seg(last.a, end, facing((end - last.a).normalized))
            for p in pending { vertexAt[p] = ch.closed ? 0 : segs.count }
        }
        // The last vertex: an open run's far end, or a closed loop's start again.
        vertexAt[n] = ch.closed ? 0 : segs.count
        if ch.closed { vertexAt[0] = 0 }
        return (segs, owners, vertexAt)
    }

    struct Traced {
        var chains: [Chain]
        var vertices: [V2]
    }

    /// The loops and runs round a set of paths (see `SurfaceTrace`). `grow`
    /// is how far the paths are from the outlines: stretches nearer than
    /// that to something that swallows them are inside it.
    static func trace(parts: [Part], paths: [[V2]], grow g: CGFloat, free: CGRect) -> Traced {
        var verts: [V2] = []
        var pathVerts: [[Int]] = []
        for p in paths {
            pathVerts.append(p.map { verts.append($0); return verts.count - 1 })
        }
        // Every segment, and where along it others cross it.
        struct S { var path: Int; var i: Int; var a: V2; var b: V2; var box: CGRect }
        var segs: [S] = []
        var first: [Int] = []
        for (pi, p) in paths.enumerated() {
            first.append(segs.count)
            for i in p.indices {
                let a = p[i], b = p[(i + 1) % p.count]
                segs.append(S(path: pi, i: i, a: a, b: b, box: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))))
            }
        }
        first.append(segs.count)
        let boxes = paths.map { Poly.bounds($0).insetBy(dx: -0.5, dy: -0.5) }
        var splits = [[(t: CGFloat, v: Int)]](repeating: [], count: segs.count)
        for pi in paths.indices {
            for pj in pi..<paths.count where boxes[pi].intersects(boxes[pj]) {
                for si in first[pi]..<first[pi + 1] {
                    let s = segs[si]
                    guard s.box.insetBy(dx: -0.5, dy: -0.5).intersects(boxes[pj]) else { continue }
                    let from = pi == pj ? si + 2 : first[pj]
                    guard from < first[pj + 1] else { continue }
                    for sj in from..<first[pj + 1] {
                        if pi == pj, si == first[pi], sj == first[pi + 1] - 1 { continue }   // (neighbours round the end)
                        let o = segs[sj]
                        guard s.box.insetBy(dx: -0.5, dy: -0.5).intersects(o.box) else { continue }
                        let r = s.b - s.a, q = o.b - o.a
                        let den = r.cross(q)
                        guard abs(den) > 1e-9 else { continue }
                        let w = o.a - s.a
                        let t = w.cross(q) / den, u = w.cross(r) / den
                        guard t > 1e-9, t < 1 - 1e-9, u > 1e-9, u < 1 - 1e-9 else { continue }
                        verts.append(s.a + r * t)
                        splits[si].append((t, verts.count - 1))
                        splits[sj].append((u, verts.count - 1))
                    }
                }
            }
        }
        // The pieces between crossings, in order round each path.
        struct Piece { var path: Int; var from: Int; var to: Int; var keep = true; var next = -1; var prev = -1 }
        var pieces: [Piece] = []
        for (pi, p) in paths.enumerated() {
            let start = pieces.count
            for i in p.indices {
                let si = first[pi] + i
                var cuts = splits[si].sorted { $0.t < $1.t }.map(\.v)
                cuts.insert(pathVerts[pi][i], at: 0)
                cuts.append(pathVerts[pi][(i + 1) % p.count])
                for k in 0..<(cuts.count - 1) { pieces.append(Piece(path: pi, from: cuts[k], to: cuts[k + 1])) }
            }
            let end = pieces.count
            for k in start..<end {
                pieces[k].next = k + 1 < end ? k + 1 : start
                pieces[k].prev = k > start ? k - 1 : end - 1
            }
        }
        // Which pieces are inside something that swallows them.
        let reach = paths.indices.map { parts[$0].box.insetBy(dx: -g - 1, dy: -g - 1) }
        // (A rounded corner's pieces come within 2% of `g` of it.)
        let tol = max(0.4, g * 0.03)
        func swallows(_ q: Int, _ p: Int) -> Bool {
            if q == p { return g > 0 && !parts[q].rim }
            if parts[q].rim || parts[q].role == .bulk { return true }
            return parts[q].group == parts[p].group && parts[p].role == .limb && !parts[p].rim
        }
        func inside(_ m: V2, _ q: Int, own: Bool) -> Bool {
            if parts[q].rim { return !free.contains(m.point) }
            guard reach[q].contains(m.point) else { return false }
            // Inside another's path — the very line the crossings were found
            // on, so a piece is in or out as a whole — or anywhere nearer its
            // outline than the body's height (where a path turning in on
            // itself folds back).
            if !own, Poly.winds(paths[q], m) { return true }
            return g > 0 && Poly.distance(parts[q].outline, m) < g - tol
        }
        for k in pieces.indices {
            let p = pieces[k].path
            let m = (verts[pieces[k].from] + verts[pieces[k].to]) * 0.5
            if verts[pieces[k].from].distance(to: verts[pieces[k].to]) < 1e-6 { pieces[k].keep = false; continue }
            for q in parts.indices where swallows(q, p) && inside(m, q, own: q == p) {
                pieces[k].keep = false
                break
            }
        }
        // What follows each piece: its own path where that goes on; else,
        // where it crosses into something, the one line leaving the
        // crossing that nothing else is already following.
        var outgoing: [Int: [Int]] = [:]
        for k in pieces.indices where pieces[k].keep { outgoing[pieces[k].from, default: []].append(k) }
        var succ = [Int](repeating: -1, count: pieces.count)
        var taken = [Bool](repeating: false, count: pieces.count)
        for k in pieces.indices where pieces[k].keep {
            let n = pieces[k].next
            if n >= 0, pieces[n].keep { succ[k] = n; taken[n] = true }
        }
        for k in pieces.indices where pieces[k].keep && succ[k] < 0 {
            let here = pieces[k].to
            let dir = (verts[here] - verts[pieces[k].from]).normalized
            let free = (outgoing[here] ?? []).filter { c in
                c != k && !taken[c] && !(pieces[c].prev >= 0 && pieces[pieces[c].prev].keep)
            }
            guard !free.isEmpty else { continue }
            let pick = free.min { a, b in
                func rank(_ c: Int) -> (Int, CGFloat) {
                    let same = pieces[c].path == pieces[k].path ? 0 : (parts[pieces[c].path].group == parts[pieces[k].path].group ? 1 : 2)
                    let d = (verts[pieces[c].to] - verts[pieces[c].from]).normalized
                    return (same, -d.dot(dir))
                }
                let ra = rank(a), rb = rank(b)
                return ra.0 != rb.0 ? ra.0 < rb.0 : ra.1 < rb.1
            }!
            succ[k] = pick
            taken[pick] = true
        }
        // Follow them: runs from their starts, then whatever goes round.
        var chains: [Chain] = []
        var seen = [Bool](repeating: false, count: pieces.count)
        func follow(_ k0: Int) {
            var ks: [Int] = []
            var k = k0
            var closed = false
            while k >= 0, !seen[k] {
                seen[k] = true
                ks.append(k)
                k = succ[k]
                if k == k0 { closed = true; break }
            }
            guard !ks.isEmpty else { return }
            var ids = ks.map { pieces[$0].from }
            if !closed { ids.append(pieces[ks.last!].to) }
            chains.append(Chain(pts: ids.map { verts[$0] }, parts: ks.map { pieces[$0].path }, vertexIDs: ids, closed: closed))
        }
        for k in pieces.indices where pieces[k].keep && !taken[k] && !seen[k] { follow(k) }
        for k in pieces.indices where pieces[k].keep && !seen[k] { follow(k) }
        return Traced(chains: mended(chains, solid: { parts[$0].rim || parts[$0].role == .bulk }), vertices: verts)
    }

    /// A run that ends right by another surface (within 2 points) but not
    /// on a point of it — where a crossing was found on one line and only
    /// just missed on the other — is tied to it there: a point is put in the
    /// other at the nearest place, and the two meet.
    static func tieLooseEnds(_ t: inout Traced) {
        var counts: [Int: Int] = [:]
        for ch in t.chains { for v in Set(ch.vertexIDs) { counts[v, default: 0] += 1 } }
        for a in t.chains.indices where !t.chains[a].closed {
            for atEnd in [false, true] {
                let ch = t.chains[a]
                let id = atEnd ? ch.vertexIDs[ch.vertexIDs.count - 1] : ch.vertexIDs[0]
                guard counts[id] == 1 else { continue }
                let p = atEnd ? ch.pts[ch.pts.count - 1] : ch.pts[0]
                var best: (chain: Int, piece: Int, t: CGFloat, d: CGFloat)?
                for b in t.chains.indices where b != a {
                    let o = t.chains[b]
                    for k in 0..<o.pieceCount {
                        let x = o.pts[k], y = o.pts[(k + 1) % o.pts.count]
                        let (tt, d) = projectOnSegment(p, x, y)
                        if d < 2, best.map({ d < $0.d }) ?? true { best = (b, k, tt, d) }
                    }
                }
                guard let hit = best else { continue }
                var o = t.chains[hit.chain]
                let x = o.pts[hit.piece], y = o.pts[(hit.piece + 1) % o.pts.count]
                let len = x.distance(to: y)
                if hit.t * len < 0.05 {
                    // (Right on a point of it already: that point.)
                    t.chains[a].vertexIDs[atEnd ? ch.vertexIDs.count - 1 : 0] = o.vertexIDs[hit.piece]
                } else if (1 - hit.t) * len < 0.05, o.closed || hit.piece + 1 < o.vertexIDs.count {
                    t.chains[a].vertexIDs[atEnd ? ch.vertexIDs.count - 1 : 0] = o.vertexIDs[(hit.piece + 1) % o.vertexIDs.count]
                } else {
                    t.vertices.append(x + (y - x) * hit.t)
                    let v = t.vertices.count - 1
                    o.pts.insert(t.vertices[v], at: hit.piece + 1)
                    o.vertexIDs.insert(v, at: hit.piece + 1)
                    o.parts.insert(o.parts[hit.piece], at: hit.piece + 1)
                    t.chains[hit.chain] = o
                    t.chains[a].vertexIDs[atEnd ? ch.vertexIDs.count - 1 : 0] = v
                    // (Its own end moves onto the point the two now share.)
                    t.chains[a].pts[atEnd ? ch.pts.count - 1 : 0] = t.vertices[v]
                }
            }
        }
    }

    /// Where several lines cross all but at one point, a run can stop a
    /// hair short of the one it should go on into. A run that ends where
    /// nothing else is (not on another surface — a real end) and with the
    /// start of a run within a few points of it goes on into that one (or,
    /// its own start, closes up).
    static func mended(_ given: [Chain], solid: (Int) -> Bool = { _ in false }) -> [Chain] {
        var chains = given
        var changed = true
        while changed {
            changed = false
            var counts: [Int: Int] = [:]
            for ch in chains { for v in Set(ch.vertexIDs) { counts[v, default: 0] += 1 } }
            for a in chains.indices where !chains[a].closed {
                guard let end = chains[a].pts.last, let endID = chains[a].vertexIDs.last else { continue }
                var best: (Int, CGFloat)?
                for b in chains.indices where !chains[b].closed {
                    let d = chains[b].pts[0].distance(to: end)
                    if d < 4, best.map({ d < $0.1 }) ?? true { best = (b, d) }
                }
                guard let (b, d) = best else { continue }
                // (Ending on another run — a limb stopping on something — is
                // a real end; but where a fold in the surface grown round
                // something solid has left two runs a hair apart, one's end
                // on a point the other passes through, the start right by it
                // is where it goes on.)
                guard counts[endID] == 1 || (d < 2 && b != a && counts[chains[b].vertexIDs[0]] == 1
                                             && chains[a].parts.last.map(solid) == true && chains[b].parts.first.map(solid) == true) else { continue }
                var A = chains[a]
                let B = chains[b]
                if d > 0.05 { A.parts.append(A.parts.last ?? B.parts[0]) }   // (a piece across the gap)
                if a == b {
                    if d <= 0.05 { A.pts.removeLast(); A.vertexIDs.removeLast() }
                    A.closed = true
                    chains[a] = A
                } else {
                    if d <= 0.05 { A.pts.removeLast(); A.vertexIDs.removeLast() }
                    A.pts += B.pts
                    A.vertexIDs += B.vertexIDs
                    A.parts += B.parts
                    chains[a] = A
                    chains.remove(at: b)
                }
                changed = true
                break
            }
        }
        return chains
    }
}
