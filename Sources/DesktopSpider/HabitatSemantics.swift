import AppKit

// MARK: - What things are, to the spider
//
// A thing in the tank is more to it than something to walk on: something to
// climb, or to sit on top of, or to get under out of the rain; wet or warm,
// grown or made; somewhere to hide, to watch from, to hang a line from.
//
// Each kind's *nature* is worked out once, by rule, from what its definition
// already says (HabitatObjects.swift) — what it is made of, what it is for,
// how it is put, how it moves in the air — and from its shape: how tall it
// is, whether it has a flat top, whether it stands over open ground, whether
// it has a hollow. Only what nothing there could tell (a lamp glows, a fire
// is warm, a bed is for sleeping on) is said by hand, in its traits'
// `extra`. Where one particular thing stands then adds its *situation*: up
// off the ground, under something, out in the open (`Habitat.qualities`).
//
// Every quality is graded, 0…1 — a leaf shelters a little, a cave a lot —
// so what reads them can weigh them rather than switch on them.
//
// Then the places on a thing that mean something (`InteractionPoint`): the
// top of it, under it, its edges, the way in, the rim of its water, a bit of
// it within reach of the front legs from beside it — each in the world,
// with the spot on the surfaces where the spider stands to use it.

/// Something a thing can be, to the spider.
enum HabitatQuality: Int, CaseIterable {
    case climbable, perchable, sheltering, hideable, drinkable, wet, movable, lightweight, flexible, hanging
    case enclosed, elevated, warm, cool, exposed, covered, organic, artificial, preyAttracting, silkAnchor
    case sleepingSuitable, lookoutSuitable, huntingSuitable, moistureSource, interesting, glowing, moving

    var label: String {
        switch self {
        case .preyAttracting: return "prey-attracting"
        case .silkAnchor: return "silk-anchor"
        case .sleepingSuitable: return "sleeping-suitable"
        case .lookoutSuitable: return "lookout-suitable"
        case .huntingSuitable: return "hunting-suitable"
        case .moistureSource: return "moisture-source"
        default: return "\(self)"
        }
    }
}

/// How much of each quality a thing has: 0 not at all … 1 through and through.
struct HabitatQualities: Equatable, CustomStringConvertible {
    private var v = [CGFloat](repeating: 0, count: HabitatQuality.allCases.count)

    subscript(_ q: HabitatQuality) -> CGFloat {
        get { v[q.rawValue] }
        set { v[q.rawValue] = clamp(newValue, 0, 1) }
    }

    /// Has at least `atLeast` of it.
    func has(_ q: HabitatQuality, _ atLeast: CGFloat = 0.5) -> Bool { self[q] >= atLeast }

    /// Up to `x`, if it has less.
    mutating func raise(_ q: HabitatQuality, _ x: CGFloat) { if x > self[q] { self[q] = x } }

    /// What it has, most first.
    var present: [(quality: HabitatQuality, amount: CGFloat)] {
        HabitatQuality.allCases.compactMap { self[$0] > 0.05 ? ($0, self[$0]) : nil }.sorted { $0.amount > $1.amount }
    }

    var description: String { present.map { String(format: "%@ %.2f", $0.quality.label, Double($0.amount)) }.joined(separator: ", ") }
}

extension HabitatItemKind {
    /// What it is to the spider, wherever it is put (see `Habitat.qualities(of:)`
    /// for one where it is). Worked out once for each kind.
    var nature: HabitatQualities { HabitatItemKind.natures[self]! }

    private static let natures: [HabitatItemKind: HabitatQualities] = Dictionary(uniqueKeysWithValues: allCases.map { ($0, NatureRules.of($0)) })
}

/// How a kind's nature is worked out from its definition and its shape.
enum NatureRules {
    static func of(_ kind: HabitatItemKind) -> HabitatQualities {
        let d = kind.definition, tr = d.traits, fn = tr.functions, m = tr.material
        let size = d.size
        let g = d.shape(CGRect(origin: .zero, size: size), 0, 1)
        let solid = d.category == .perch && !g.parts.isEmpty
        let water = fn.contains(.water) || m == .water
        let hollow = !g.hollows.isEmpty || g.anchors.contains { $0.kind == .refuge || $0.kind == .entrance }
        let sway = clamp(d.sway / 0.03, 0, 1)
        let over = solid ? overhang(g, size: size, aloft: d.placement == .wedged || d.placement == .hangs) : 0
        // (Leaves and flowers drawn round it, as a share of its box.)
        let foliage = g.visual.reduce(0) { $0 + abs(Poly.area($1)) } / max(size.width * size.height, 1)
        var q = HabitatQualities()

        // Its shape: what there is to climb and to sit on, and what it holds
        // up over the ground.
        q[.climbable] = solid ? clamp(0.55 + size.height / 250, 0.55, 1) : 0
        q[.perchable] = solid ? max(clamp(widestFlat(g) / 40, 0, 1), g.anchors.contains { $0.kind == .perch } ? 0.8 : 0) : 0
        q[.sheltering] = max(fn.contains(.cover) || fn.contains(.retreat) ? 1 : 0, hollow ? 0.85 : 0, over)
        q[.hideable] = max(fn.contains(.retreat) ? 1 : 0, hollow ? 0.9 : 0, clamp(foliage * 1.2, 0, 0.6),
                           kind.canGoInFront && size.height > 30 ? 0.4 : 0)
        q[.enclosed] = max(hollow ? 1 : 0, fn.contains(.retreat) ? 0.9 : 0, fn.contains(.cover) ? 0.35 : 0)
        q[.elevated] = max(fn.contains(.lookout) ? 1 : 0, d.placement == .hangs ? 0.8 : 0, solid ? clamp((size.height - 120) / 200, 0, 0.6) : 0)
        q[.hanging] = d.placement == .hangs ? 1 : 0

        // Water and damp.
        q[.drinkable] = water ? 1 : 0
        q[.wet] = max(water ? 0.9 : 0, fn.contains(.humid) ? 0.7 : 0, tr.niche.damp ? 0.3 : 0)
        q[.moistureSource] = max(water ? 1 : 0, fn.contains(.humid) ? 0.9 : 0, tr.niche.damp ? 0.45 : 0, m == .moss ? 0.4 : 0)
        q[.warm] = max(fn.contains(.basking) ? 1 : 0, m == .stone ? 0.25 : 0)
        q[.cool] = max(water ? 0.8 : 0, fn.contains(.humid) ? 0.7 : 0, m == .moss ? 0.5 : 0, tr.niche.damp ? 0.4 : 0, hollow ? 0.45 : 0, over * 0.4)

        // What it is made of, and how it moves.
        q[.organic] = m.organic ? 1 : 0
        q[.artificial] = m == .made || !d.shelf.natural ? 1 : 0
        q[.movable] = tr.loose != nil ? 1 : 0
        q[.lightweight] = tr.loose.map { clamp(1.2 - $0.mass / 8, 0.2, 1) } ?? 0
        q[.flexible] = max(sway, [.leaf, .stem, .feather, .moss].contains(m) ? 0.45 : 0, d.placement == .hangs && d.stretch == .vertical ? 0.6 : 0)
        q[.moving] = max(sway, tr.loose != nil ? 0.25 : 0)

        // What it is good for.
        q[.preyAttracting] = max(fn.contains(.feeding) ? 1 : 0, d.group == .flowering ? 0.75 : 0, water ? 0.4 : 0,
                                 m == .fungus || (d.group == .leaves && m == .leaf) ? 0.35 : 0, tr.niche.damp ? 0.3 : 0)
        q[.silkAnchor] = max(fn.contains(.silk) ? 1 : 0, g.anchors.contains { $0.kind == .tie } ? 0.8 : 0,
                             solid && g.parts.contains { $0.role == .limb } ? 0.6 : 0, over * 0.7, solid ? 0.25 : 0)
        q[.sleepingSuitable] = max(fn.contains(.retreat) ? 1 : 0, hollow ? 0.8 : 0, fn.contains(.cover) ? 0.55 : 0, over * 0.4)
        q[.lookoutSuitable] = max(fn.contains(.lookout) ? 1 : 0, q[.perchable] * clamp((size.height - 60) / 180, 0, 0.8))

        // What nothing above could tell.
        for (k, x) in tr.extra { q.raise(k, x) }

        // And what follows from all that.
        q.raise(.huntingSuitable, max(q[.preyAttracting] * max(q[.perchable], q[.climbable] * 0.6), q[.lookoutSuitable] * 0.6))
        q.raise(.interesting, 0.35 + 0.25 * q[.glowing] + 0.2 * q[.moving] + (hollow ? 0.15 : 0) + 0.1 * q[.drinkable]
                    + 0.1 * q[.preyAttracting] + (g.parts.count > 3 ? 0.1 : 0))
        return q
    }

    /// The widest stretch of its tops that is near enough flat to sit on.
    static func widestFlat(_ g: ObjectGeometry) -> CGFloat {
        var best: CGFloat = 0
        for line in g.topLines(step: 4) {
            var run: CGFloat = 0
            for i in 1..<line.count {
                let a = line[i - 1], b = line[i]
                let dx = abs(b.x - a.x)
                if dx > 0.01, abs(b.y - a.y) / dx < 0.35 { run += dx } else { run = 0 }
                best = max(best, run)
            }
        }
        return best
    }

    /// How much of its width stands over open space a spider could get
    /// under, 0…1 — the cap of a toadstool, the arch of a root. Something
    /// put up in the air (`aloft`: a branch, a hanging thing) is over open
    /// space wherever there is any of it.
    static func overhang(_ g: ObjectGeometry, size: CGSize, aloft: Bool) -> CGFloat {
        let b = g.bounds
        guard !b.isNull, b.width > 1 else { return 0 }
        let n = 24
        var clear = 0, some = 0
        for k in 0..<n {
            let x = b.minX + b.width * (CGFloat(k) + 0.5) / CGFloat(n)
            var low = CGFloat.greatestFiniteMagnitude
            for part in g.parts {
                let o = part.outline
                for i in o.indices {
                    let a = o[i], c = o[(i + 1) % o.count]
                    guard (a.x - x) * (c.x - x) <= 0, abs(c.x - a.x) > 1e-6 else { continue }
                    low = min(low, a.y + (c.y - a.y) * (x - a.x) / (c.x - a.x))
                }
            }
            guard low < .greatestFiniteMagnitude else { continue }
            some += 1
            // (Room under it for the body: about 30 points.)
            if aloft || low >= b.minY + 30 { clear += 1 }
        }
        guard some > 0 else { return 0 }
        let share = CGFloat(clear) / CGFloat(n)
        // Too narrow to be over much of anything counts for less.
        return clamp(share * clamp(share * b.width / 50, 0, 1) * (aloft ? 0.8 : 1), 0, 1)
    }
}

extension Habitat {
    /// What a thing in it is to the spider: its kind's nature, and where it
    /// is — up off the ground, with something over it or out in the open,
    /// hung from something.
    func qualities(of it: HabitatItem) -> HabitatQualities {
        var q = it.kind.nature
        let up = it.kind.hangs ? CGFloat(1) : min(max((it.y - 24) / 140, 0), 1)
        q.raise(.elevated, up)
        let roof = cover(over: it)
        q[.covered] = max(roof, q[.enclosed] * 0.8)
        q[.exposed] = 1 - roof
        if it.kind.hangs, links.contains(where: { $0.child == it.uid }) { q[.hanging] = 1 }
        if up > 0.3 { q.raise(.lookoutSuitable, q[.perchable] * up * 0.7) }
        return q
    }

    /// How much of the top of it has something over it, near enough above
    /// to keep the weather off: 0…1.
    func cover(over it: HabitatItem) -> CGFloat {
        let r = it.rect
        guard r.width > 1 else { return 0 }
        var spans: [(CGFloat, CGFloat)] = []
        for o in items where o.id != it.id && !o.kind.isBacking && o.kind.definition.layer != .rear && !o.kind.definition.shelf.isGround {
            let q = o.rect
            guard q.maxX > r.minX, q.minX < r.maxX, q.minY >= r.maxY - 6, q.minY - r.maxY < 320 else { continue }
            spans.append((max(q.minX, r.minX), min(q.maxX, r.maxX)))
        }
        spans.sort { $0.0 < $1.0 }
        var len: CGFloat = 0, reach = r.minX
        for (a, b) in spans where b > reach {
            len += b - max(a, reach)
            reach = b
        }
        return min(max(len / r.width, 0), 1)
    }
}

extension HabitatObjectDefinition.Shelf {
    /// Lies flat on the ground: gravel, a drift of sand.
    var isGround: Bool { self == .ground }
}

// MARK: - The places on a thing

/// A place on a thing that means something — a bit of it to touch, its top,
/// under it, its edge, the way in, the rim of its water — in the world, with
/// the spot on the surfaces where the spider stands to use it.
struct InteractionPoint {
    enum Kind: String, CaseIterable {
        /// On the ground near it, far enough off to take it all in.
        case inspect
        /// A bit of it within reach of the front legs, from beside it.
        case touch
        /// Its top, standing on it.
        case top
        /// A flat top to sit on.
        case perch
        /// Its underside, hanging from it.
        case underside
        /// The ground under it, looking up at its underside.
        case beneath
        /// Up its side.
        case side
        /// The end of a slender part: a tip, the rim of a cap, the point of a leaf.
        case edge
        /// The way into it.
        case entrance
        /// The room inside it.
        case interior
        /// High and open: somewhere to leap from.
        case launch
        /// Somewhere to fasten silk.
        case silkAnchor
        /// The rim of its water, to drink at.
        case drinkEdge
        /// The water itself.
        case waterSurface
        case bask, lookout, feed
    }
    var kind: Kind
    /// Which part of it: "cap", "stem", "leaf", "rim"…
    var part: String
    /// On it, in the world.
    var point: V2
    /// Out from it there.
    var normal: V2
    /// Where the spider stands to use it — the body's spot on the surfaces —
    /// if it can stand anywhere for it at all.
    var stand: Anchor?
    var standPoint: V2?
    /// Standing there, which way along the surface it faces it (+1: toward
    /// the segment's `b`).
    var facing: CGFloat = 1

    var label: String { "\(kind.rawValue) (\(part))" }
}

extension HabitatItem {
    /// Its places that mean something (see `InteractionPoint`), on the
    /// surfaces of `map` as they are laid out now. (`fromBeside`: the bits
    /// of it within reach from beside it, and the spots to take it in from
    /// — the dearest of them to find.)
    func interactionPoints(on map: SurfaceMap, fromBeside: Bool = true) -> [InteractionPoint] {
        let g = geometry
        let r = rect
        let off = map.standoff
        let sc = off / 22
        let ground = HabitatLayout.ground
        var out: [InteractionPoint] = []
        func part(near p: V2) -> String {
            g.parts.min { Poly.distance($0.outline, p) < Poly.distance($1.outline, p) }?.name ?? (g.visual.isEmpty ? "body" : "leaves")
        }

        // Its own surfaces, in runs that face one way.
        struct Run { var loop: SurfaceLoop; var idx: [Int]; var facing: EdgeFacing }
        var runs: [Run] = []
        for l in map.loops where l.owners.contains(id) {
            var cur: Run?
            for (i, s) in l.segs.enumerated() {
                let mine = i < l.owners.count && l.owners[i] == id
                if mine, let c = cur, c.facing == s.facing, c.idx.last == i - 1 { cur!.idx.append(i); continue }
                if let c = cur { runs.append(c) }
                cur = mine ? Run(loop: l, idx: [i], facing: s.facing) : nil
            }
            if let c = cur { runs.append(c) }
        }
        func length(_ run: Run) -> CGFloat { run.idx.reduce(0) { $0 + run.loop.segs[$1].len } }
        /// The spot `f` of the way along a run: where the body is, and the
        /// surface under it.
        func spot(_ run: Run, _ f: CGFloat) -> (anchor: Anchor, body: V2, surface: V2, normal: V2) {
            var want = length(run) * f
            for (k, i) in run.idx.enumerated() {
                let s = run.loop.segs[i]
                if want <= s.len || k == run.idx.count - 1 {
                    let t = clamp(want, 0, s.len)
                    let body = s.point(at: t)
                    return (Anchor(loopID: run.loop.id, segIdx: i, t: t), body, body - s.dir.perp * off, s.dir.perp)
                }
                want -= s.len
            }
            let s = run.loop.segs[run.idx[0]]
            return (Anchor(loopID: run.loop.id, segIdx: run.idx[0], t: 0), s.a, s.a - s.dir.perp * off, s.dir.perp)
        }
        func put(_ kind: InteractionPoint.Kind, _ run: Run, _ f: CGFloat) {
            let s = spot(run, f)
            out.append(InteractionPoint(kind: kind, part: part(near: s.surface), point: s.surface, normal: s.normal,
                                        stand: s.anchor, standPoint: s.body))
        }

        // Its tops: the highest, somewhere flat to sit, and the ends of the
        // high ones to leap from.
        let tops = runs.filter { $0.facing == .up && length($0) >= 6 * sc }
            .sorted { spot($0, 0.5).body.y > spot($1, 0.5).body.y }
        if let high = tops.first {
            let ys = (0...8).map { spot(high, CGFloat($0) / 8) }
            let peak = ys.max { $0.body.y < $1.body.y }!
            out.append(InteractionPoint(kind: .top, part: part(near: peak.surface), point: peak.surface, normal: peak.normal,
                                        stand: peak.anchor, standPoint: peak.body))
        }
        for run in tops where length(run) >= 16 * sc {
            let a = spot(run, 0).body, b = spot(run, 1).body
            if abs(b.y - a.y) < abs(b.x - a.x) * 0.35 { put(.perch, run, 0.5) }
        }
        for run in tops.prefix(2) where spot(run, 0.5).surface.y - ground > 40 {
            put(.launch, run, 0.12)
            put(.launch, run, 0.88)
        }

        // Its undersides: to hang from, and to look up at from under them.
        let unders = runs.filter { $0.facing == .down && length($0) >= 8 * sc }.sorted { length($0) > length($1) }
        for run in unders.prefix(3) {
            put(.underside, run, 0.5)
            put(.silkAnchor, run, 0.5)
            let u = spot(run, 0.5).surface
            if let f = HabitatItem.floor(below: u, on: map, notOwnedBy: id), u.y - (f.point.y - off) >= off * 1.5 {
                out.append(InteractionPoint(kind: .beneath, part: part(near: u), point: u, normal: V2(0, -1),
                                            stand: f.anchor, standPoint: f.point))
            }
        }

        // Up its sides.
        for facing in [EdgeFacing.left, .right] {
            for run in runs.filter({ $0.facing == facing && length($0) >= 10 * sc }).sorted(by: { length($0) > length($1) }).prefix(2) {
                put(.side, run, 0.5)
            }
        }

        // The ends of its slender parts (not those sunk in the ground, or
        // in the rest of it).
        for (pi, p) in g.parts.enumerated() where p.role == .limb && p.outline.count >= 3 {
            let o = p.outline
            let c = o.reduce(V2.zero, +) / CGFloat(o.count)
            let a = o.max { $0.distance(to: c) < $1.distance(to: c) }!
            let b = o.max { $0.distance(to: a) < $1.distance(to: a) }!
            for e in [a, b] {
                guard kind.hangs || e.y > ground + 4, !kind.hangs || e.y < r.maxY - 4 else { continue }
                guard !g.parts.indices.contains(where: { $0 != pi && Poly.contains(g.parts[$0].outline, e) }) else { continue }
                let n = (e - c).normalized
                let st = HabitatItem.spot(on: map, near: e + n * off, within: off * 2, ownedBy: id)
                out.append(InteractionPoint(kind: .edge, part: p.name, point: e, normal: n, stand: st?.anchor, standPoint: st?.point))
                if n.y < 0.5 { out.append(InteractionPoint(kind: .silkAnchor, part: p.name, point: e, normal: n, stand: st?.anchor, standPoint: st?.point)) }
            }
        }

        // From beside it, on whatever is round it: a bit of it within reach
        // of the front legs, and somewhere a little way off to take it in.
        let outlines = g.parts.isEmpty ? g.visual : g.parts.map(\.outline)
        if fromBeside, !outlines.isEmpty {
            func nearest(to p: V2) -> V2 {
                var best = (d: CGFloat.greatestFiniteMagnitude, q: p)
                for o in outlines {
                    for i in o.indices {
                        let a = o[i], b = o[(i + 1) % o.count]
                        let (t, d) = projectOnSegment(p, a, b)
                        if d < best.d { best = (d, a + (b - a).normalized * t) }
                    }
                }
                return best.q
            }
            // (A front leg feeling something is held up and out ahead, all
            // but straight: about 33 of its 43 units, 25° up from the hip.)
            let reach = 33 * sc, lift: CGFloat = 0.44
            var touch: [CGFloat: (score: CGFloat, p: InteractionPoint)] = [:]
            var look: [CGFloat: (score: CGFloat, p: InteractionPoint)] = [:]
            let near = r.insetBy(dx: -170 * sc, dy: -120 * sc)
            for s in HabitatItem.spots(on: map, in: near, spacing: 5 * sc) where s.owner != id && s.seg.dir.perp.y > 0.6 {
                let side: CGFloat = s.point.x < r.midX ? -1 : 1
                let q = nearest(to: s.point)
                // (Facing the middle of it: under a cap the nearest of it is
                // overhead, not ahead.)
                let toward: CGFloat = -side
                let facing: CGFloat = s.seg.dir.x * toward >= 0 ? 1 : -1
                // (The hips are a little ahead of the middle and down.)
                let hip = s.point + V2(toward * 7 * sc, -7 * sc)
                let feet = s.point.y - off
                // Where the raised front legs would be: the nearest of it to
                // there is what they touch, from the spot where it is nearest.
                let tip = hip + V2(toward * cos(lift), sin(lift)) * reach
                let p = nearest(to: tip)
                let miss = p.distance(to: tip), d = p.distance(to: hip)
                if p.y > feet + 1, (p.x - hip.x) * toward > 8 * sc, d > 18 * sc, d < 38 * sc, miss < 9 * sc {
                    if miss < touch[side]?.score ?? .greatestFiniteMagnitude {
                        touch[side] = (miss, InteractionPoint(kind: .touch, part: part(near: p), point: p, normal: (hip - p).normalized,
                                                              stand: s.anchor, standPoint: s.point, facing: facing))
                    }
                }
                let gap = q.distance(to: s.point)
                if gap > 55 * sc, gap < 170 * sc, abs(feet - max(r.minY, ground)) < 60 * sc || kind.hangs || y > 30 {
                    let score = abs(gap - 95 * sc)
                    if score < look[side]?.score ?? .greatestFiniteMagnitude {
                        look[side] = (score, InteractionPoint(kind: .inspect, part: part(near: q), point: q, normal: (s.point - q).normalized,
                                                              stand: s.anchor, standPoint: s.point, facing: facing))
                    }
                }
            }
            out += touch.values.map(\.p) + look.values.map(\.p)
        }

        // Water: the water itself, and its rim to drink at.
        if kind.nature.has(.drinkable) {
            let top = g.top(from: r.minX + r.width * 0.3, to: r.maxX - r.width * 0.3) ?? (r.maxY - 2)
            out.append(InteractionPoint(kind: .waterSurface, part: "water", point: V2(r.midX, top), normal: V2(0, 1)))
            let drinks = g.anchors.filter { $0.kind == .drink }.map(\.point)
            for e in drinks.isEmpty ? [V2(r.minX + r.width * 0.16, top), V2(r.maxX - r.width * 0.16, top)] : drinks {
                let st = HabitatItem.spot(on: map, near: e + V2(0, off), within: off * 2.5, ownedBy: nil)
                out.append(InteractionPoint(kind: .drinkEdge, part: "rim", point: e, normal: V2(0, 1), stand: st?.anchor, standPoint: st?.point))
            }
        }

        // What its shape says it has: a spot to sit, to tie silk to, a way
        // in, a warm top, a view, a tray for food.
        for a in g.anchors {
            let kind: InteractionPoint.Kind
            switch a.kind {
            case .perch: kind = .perch
            case .tie: kind = .silkAnchor
            case .entrance: kind = .entrance
            case .refuge: kind = .interior
            case .drink: continue
            case .bask: kind = .bask
            case .lookout: kind = .lookout
            case .feed: kind = .feed
            }
            let st = HabitatItem.spot(on: map, near: a.point + a.normal * off, within: off * 2.5, ownedBy: nil)
            out.append(InteractionPoint(kind: kind, part: part(near: a.point), point: a.point, normal: a.normal, stand: st?.anchor, standPoint: st?.point))
        }
        for h in g.hollows {
            let st = HabitatItem.spot(on: map, near: h.mouth - h.inward * off * 0.5 + V2(0, off), within: off * 3, ownedBy: nil)
            out.append(InteractionPoint(kind: .entrance, part: "mouth", point: h.mouth, normal: -h.inward, stand: st?.anchor, standPoint: st?.point))
            let c = h.cavity.reduce(V2.zero, +) / CGFloat(max(h.cavity.count, 1))
            let inside = HabitatItem.spot(on: map, near: c, within: off * 3, ownedBy: nil).flatMap { Poly.contains(h.cavity, $0.point) ? $0 : nil }
            out.append(InteractionPoint(kind: .interior, part: "hollow", point: c, normal: -h.inward, stand: inside?.anchor, standPoint: inside?.point))
        }

        // (One of each kind to a spot — had from the same place: either side
        // of a thin stem is two.)
        var kept: [InteractionPoint] = []
        for p in out where !kept.contains(where: {
            $0.kind == p.kind && $0.point.distance(to: p.point) < 6 && ($0.standPoint ?? $0.point).distance(to: p.standPoint ?? p.point) < 12
        }) { kept.append(p) }
        return kept
    }

    /// Spots on the surfaces within `r`, every `spacing` along them — short
    /// segments too (a curve is made of them) — with what each is the
    /// surface of (0: the tank).
    static func spots(on map: SurfaceMap, in r: CGRect, spacing: CGFloat) -> [(anchor: Anchor, point: V2, seg: Seg, owner: Int)] {
        var out: [(Anchor, V2, Seg, Int)] = []
        let step = max(spacing, 2)
        for l in map.loops {
            var carry: CGFloat = 0
            for (i, s) in l.segs.enumerated() {
                // (Padded: a flat stretch of floor has no height, and an empty
                // box meets nothing.)
                let box = CGRect(x: min(s.a.x, s.b.x) - 1, y: min(s.a.y, s.b.y) - 1, width: abs(s.b.x - s.a.x) + 2, height: abs(s.b.y - s.a.y) + 2)
                guard box.intersects(r) else { carry = 0; continue }
                var t = carry
                while t < s.len {
                    let p = s.point(at: t)
                    if r.contains(p.point) { out.append((Anchor(loopID: l.id, segIdx: i, t: t), p, s, i < l.owners.count ? l.owners[i] : 0)) }
                    t += step
                }
                carry = t - s.len
            }
        }
        return out.map { (anchor: $0.0, point: $0.1, seg: $0.2, owner: $0.3) }
    }

    /// The nearest spot on the surfaces to `p` within `within` — on this
    /// thing's own (`ownedBy`), or on anything.
    static func spot(on map: SurfaceMap, near p: V2, within: CGFloat, ownedBy owner: Int?) -> (anchor: Anchor, point: V2)? {
        var best: (d: CGFloat, a: Anchor, p: V2)?
        for l in map.loops {
            for (i, s) in l.segs.enumerated() {
                if let owner, !(i < l.owners.count && l.owners[i] == owner) { continue }
                let (t, d) = projectOnSegment(p, s.a, s.b)
                if d < within, d < best?.d ?? .greatestFiniteMagnitude { best = (d, Anchor(loopID: l.id, segIdx: i, t: t), s.point(at: t)) }
            }
        }
        return best.map { ($0.a, $0.p) }
    }

    /// The top of whatever is under `p` (not this thing): the body's spot
    /// standing on it.
    static func floor(below p: V2, on map: SurfaceMap, notOwnedBy owner: Int) -> (anchor: Anchor, point: V2)? {
        var best: (y: CGFloat, a: Anchor, p: V2)?
        for l in map.loops {
            for (i, s) in l.segs.enumerated() where s.facing == .up {
                if i < l.owners.count, l.owners[i] == owner { continue }
                let lo = min(s.a.x, s.b.x), hi = max(s.a.x, s.b.x)
                guard p.x >= lo, p.x <= hi, hi - lo > 0.5 else { continue }
                let t = abs(p.x - s.a.x) / abs(s.b.x - s.a.x) * s.len
                let q = s.point(at: t)
                guard q.y < p.y, q.y > best?.y ?? -.greatestFiniteMagnitude else { continue }
                best = (q.y, Anchor(loopID: l.id, segIdx: i, t: t), q)
            }
        }
        return best.map { ($0.a, $0.p) }
    }
}

// MARK: - What changed

/// What changed in the tank between one moment and the next: things put
/// in, taken out, moved about or reshaped — by who each thing is (`uid`).
struct HabitatChange {
    var added: [HabitatItem] = []
    var removed: [HabitatItem] = []
    var moved: [(was: HabitatItem, now: HabitatItem)] = []
    /// Resized, flipped, or turned into its other self (a door opened).
    var reshaped: [(was: HabitatItem, now: HabitatItem)] = []
    /// Hardly anything is as it was: a different tank altogether.
    var overhaul = false

    var count: Int { added.count + removed.count + moved.count + reshaped.count }
    var isEmpty: Bool { count == 0 }

    init() {}

    init(from a: Habitat, to b: Habitat) {
        let before = Dictionary(a.items.map { ($0.uid, $0) }, uniquingKeysWith: { x, _ in x })
        let after = Set(b.items.map(\.uid))
        for it in b.items {
            guard let was = before[it.uid] else { added.append(it); continue }
            if abs(was.x - it.x) > 1 || abs(was.y - it.y) > 1 { moved.append((was, it)) }
            if abs(was.w - it.w) > 1 || abs(was.h - it.h) > 1 || was.flipped != it.flipped || was.kind != it.kind { reshaped.append((was, it)) }
        }
        removed = a.items.filter { !after.contains($0.uid) }
        let kept = b.items.count - added.count
        overhaul = b.items.count > 4 && kept < b.items.count / 2
    }
}
