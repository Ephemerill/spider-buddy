import CoreGraphics
import Foundation

// MARK: - Places, and what they are good for
//
// HabitatSemantics.swift says what each *thing* in the tank is. This is
// about *where*: the spots it could go to for something — to drink, to get
// out of the weather, to hide, to sleep, to watch from, to warm up.
//
// Every spot on the surfaces, and every named place on a thing (the rim of
// its water, the way into a cave, the top of a stump: `InteractionPoint`),
// is sized up once for each layout of the tank (`PlaceSurvey`), for what
// it offers as it stands: how much is over it and how near, and whether
// that was built or grew (`made`); how shut in it is; how high; how much
// of the tank it looks out over; how warm and damp it is round there; what
// draws prey near; whether it can be walked to from the floor at all. All
// of it graded 0…1, from the shapes themselves — never from what a thing
// is called: a table is as much a roof as a bark cave, and the top of a
// stump as much a lookout as the lookout.
//
// What the spider has made of a place over time — how often it has been
// there, what it has liked it for, a fright it had there, a catch it made
// there (`PlaceRecord`, in HabitatKnowledge.swift) — and what is going on
// just now (a fright, the weather, the pointer bustling about) are added
// when it chooses (`PlaceSurvey.appeal`). Each thing it goes somewhere for
// weighs them its own way: a bed wants cover, quiet and the familiar; a
// lookout height and a view; a hiding place to be shut in, away from what
// frightened it. And cover the keeper built — a roof, a floor overhead, a
// room, a table — counts for more than any cover that grew there: the
// house was made for it, and it takes to it.
//
// None of this is ever shown: it only shows in where it goes.

/// Something a place can offer, graded 0…1.
enum PlaceQuality: Int, CaseIterable {
    /// Out of the weather, all told.
    case shelter
    /// Up off the floor.
    case elevation
    /// Out in the open.
    case exposure
    case warmth, moisture
    /// How much of the tank it looks out over.
    case visibility
    /// Something over it, near enough to keep off the rain.
    case cover
    /// Shut in: cover, and walls either side.
    case enclosure
    /// Of the cover and walls there, how much was built by hand.
    case made
    /// Where prey comes to.
    case preyActivity
    case familiarity, safety, novelty, disturbance
    /// Somewhere to fasten silk.
    case silk
    case rest, hunting
    /// Water to drink, right there.
    case water
    /// It can walk there from the floor (not only with a leap, or through a
    /// shut door).
    case access

    var label: String { "\(self)" }
}

/// How much of each a place has.
struct PlaceQualities: CustomStringConvertible {
    private var v = [CGFloat](repeating: 0, count: PlaceQuality.allCases.count)

    subscript(_ q: PlaceQuality) -> CGFloat {
        get { v[q.rawValue] }
        set { v[q.rawValue] = clamp(newValue, 0, 1) }
    }

    var description: String {
        PlaceQuality.allCases.compactMap { self[$0] > 0.05 ? String(format: "%@ %.2f", $0.label, Double(self[$0])) : nil }.joined(separator: ", ")
    }
}

/// What it might go somewhere for.
enum PlaceUse: String, CaseIterable {
    case sleep, rest, shelter, hide, lookout, drink, hunt, bask, perch
}

/// A place in the tank: where it stands, what it is at, and what it offers.
struct HabitatPlace {
    /// Who the place is, for its memory: on a thing, by the thing's `uid` and
    /// where on it (so it goes where the thing is moved); on the tank, by
    /// where in the world.
    var key: String
    /// A named place on a thing; nil, anywhere else on the surfaces.
    var kind: InteractionPoint.Kind?
    /// Against the glass at one end of the tank.
    var glass = false
    var anchor: Anchor
    /// The body's spot there.
    var point: V2
    var facing: EdgeFacing
    /// What it stands on (a thing's `id`; 0 the tank) — and what the place
    /// is about (the dish, for the rim it drinks from), and what is over it.
    var owner: Int
    var thing: Int
    var roofOwner = 0
    /// What it looks at there: the water, the thing, out over the tank.
    var focus: V2?
    /// Standing there, the way along the surface it faces (+1: toward the
    /// segment's `b`) — at the water, out of a shelter, out over the view.
    var along: CGFloat = 1
    var q = PlaceQualities()

    var standing: Bool { facing == .up }
    var hanging: Bool { facing == .down }
}

extension HabitatItemKind {
    /// Where on it there is open water, as fractions of its rectangle (the
    /// same the picture shows).
    var waterArea: CGRect? {
        switch self {
        case .waterDish: return CGRect(x: 0.1, y: 0.45, width: 0.8, height: 0.36)
        case .rockPool: return CGRect(x: 0.16, y: 0.75, width: 0.68, height: 0.16)
        case .puddle: return CGRect(x: 0.08, y: 0.05, width: 0.84, height: 0.8)
        default: return nil
        }
    }

    /// Made by hand to be lived in or with — timber, the house kit, the
    /// furniture — as against grown, found or fixed to the wall.
    var builtForIt: Bool { [.built, .building, .home, .decor].contains(definition.shelf) }
}

extension HabitatItem {
    /// Its open water, in the world.
    var water: CGRect? {
        kind.waterArea.map { f in CGRect(x: rect.minX + rect.width * f.minX, y: rect.minY + rect.height * f.minY, width: rect.width * f.width, height: rect.height * f.height) }
    }
}

/// What it has in mind, choosing somewhere.
struct PlaceWant {
    var use: PlaceUse
    var from: V2
    var scale: CGFloat
    var personality: Personality
    /// Hiding from something there.
    var threat: V2?
    /// Coming down hard out there.
    var rough = false
    /// How hard the sun is out.
    var sun: CGFloat = 0
}

/// What it has made of a place, and of what is going on there now.
struct PlaceSense {
    var record: PlaceRecord?
    /// How it feels about the thing it is at, -1…1.
    var thingFond: CGFloat = 0
    /// What is going on there just now: the pointer bustling about, things
    /// being moved, a gale shaking it. 0…1.
    var disturbance: CGFloat = 0
    /// What the tank is like there just now (HabitatEcology.swift): stone
    /// warmed through by the sun, 0…1; and how much prey comes by, 0…1.
    var warm: CGFloat = 0
    var prey: CGFloat = 0
}

// MARK: - The survey

/// Every place in the tank as it is laid out now, sized up (see the top of
/// the file). Made again whenever the layout changes.
final class PlaceSurvey {
    private(set) var places: [HabitatPlace] = []
    private var byKey: [String: Int] = [:]
    /// Water: each thing with water in it, and where to drink from it.
    struct Water { var uid: String; var id: Int; var surface: CGRect; var drinks: [Int] }
    private(set) var water: [Water] = []
    /// Shut doors, and a spot on the floor either side to go through from.
    struct Door { var id: Int; var rect: CGRect; var sides: [(anchor: Anchor, point: V2)] }
    private(set) var doors: [Door] = []
    /// The surfaces it can walk to from the floor of the tank.
    private(set) var walkable: Set<String> = []
    let world: CGRect
    /// The body's height standing on the floor.
    let floor: CGFloat

    /// The back wall and its hardware, and what lies flat on the ground,
    /// are no places to it.
    static func counts(_ it: HabitatItem) -> Bool {
        !it.kind.isBacking && it.kind.definition.layer != .rear && it.kind.definition.shelf != .walls
    }

    init(_ h: Habitat, map: SurfaceMap, scale sc: CGFloat) {
        let off = map.standoff
        world = CGRect(origin: .zero, size: h.size)
        floor = HabitatLayout.ground + off
        let items = Dictionary(h.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var quals: [Int: HabitatQualities] = [:]
        for it in h.items { quals[it.id] = h.qualities(of: it) }
        func built(_ id: Int) -> Bool { items[id]?.kind.builtForIt ?? false }

        // Walkable from the floor.
        if map.loop("screen:0") != nil {
            let out = Dictionary(grouping: map.junctions, by: \.from)
            var frontier = ["screen:0"]
            walkable = ["screen:0"]
            while let l = frontier.popLast() {
                for j in out[l] ?? [] where !walkable.contains(j.to) {
                    walkable.insert(j.to)
                    frontier.append(j.to)
                }
            }
        }

        // The surfaces as plain segments, with what each is the surface of.
        struct S { var a: V2; var b: V2; var facing: EdgeFacing; var owner: Int; var rim: Bool; var box: CGRect }
        var segs: [S] = []
        for l in map.loops {
            for (i, s) in l.segs.enumerated() {
                let box = CGRect(x: min(s.a.x, s.b.x), y: min(s.a.y, s.b.y), width: abs(s.b.x - s.a.x), height: abs(s.b.y - s.a.y))
                segs.append(S(a: s.a, b: s.b, facing: s.facing, owner: i < l.owners.count ? l.owners[i] : 0, rim: l.kind == .screenBorder, box: box))
            }
        }
        let lid = segs.filter { $0.rim && $0.owner == 0 }.reduce(-CGFloat.greatestFiniteMagnitude) { max($0, $1.a.y, $1.b.y) } - 2
        // (Filed by where they are, so each look only goes through those
        // that could be in the way: undersides by column, sides by row,
        // everything by square.)
        let band: CGFloat = 64, cellSide: CGFloat = 128
        func col(_ x: CGFloat) -> Int { Int((x / band).rounded(.down)) }
        var downs: [Int: [Int]] = [:], lefts: [Int: [Int]] = [:], rights: [Int: [Int]] = [:], cells: [Int: [Int]] = [:]
        func cellKey(_ cx: Int, _ cy: Int) -> Int { cx &* 100_003 &+ cy }
        for (i, s) in segs.enumerated() {
            switch s.facing {
            case .down: for c in col(s.box.minX)...col(s.box.maxX) { downs[c, default: []].append(i) }
            case .left: for r in col(s.box.minY - 2)...col(s.box.maxY + 2) { lefts[r, default: []].append(i) }
            case .right: for r in col(s.box.minY - 2)...col(s.box.maxY + 2) { rights[r, default: []].append(i) }
            case .up: break
            }
            let x0 = Int((s.box.minX / cellSide).rounded(.down)), x1 = Int((s.box.maxX / cellSide).rounded(.down))
            let y0 = Int((s.box.minY / cellSide).rounded(.down)), y1 = Int((s.box.maxY / cellSide).rounded(.down))
            for cx in x0...x1 { for cy in y0...y1 { cells[cellKey(cx, cy), default: []].append(i) } }
        }

        func yAt(_ s: S, _ x: CGFloat) -> CGFloat { abs(s.b.x - s.a.x) > 0.01 ? s.a.y + (s.b.y - s.a.y) * (x - s.a.x) / (s.b.x - s.a.x) : s.box.maxY }
        // The undersides themselves (the edges, not the line the body
        // follows under them, which runs on past their ends): whose each is
        // from the body line just under it.
        var roofs: [S] = [], roofCols: [Int: [Int]] = [:]
        for l in map.loops {
            for e in l.edge where e.facing == .down {
                let m = (e.a + e.b) * 0.5
                var owner = 0, best = CGFloat.greatestFiniteMagnitude
                for i in downs[col(m.x)] ?? [] {
                    let s = segs[i]
                    guard m.x >= s.box.minX - 1, m.x <= s.box.maxX + 1 else { continue }
                    let d = abs(yAt(s, m.x) - (m.y - off))
                    if d < best { best = d; owner = s.owner }
                }
                let box = CGRect(x: min(e.a.x, e.b.x), y: min(e.a.y, e.b.y), width: abs(e.b.x - e.a.x), height: abs(e.b.y - e.a.y))
                for c in col(box.minX)...col(box.maxX) { roofCols[c, default: []].append(roofs.count) }
                roofs.append(S(a: e.a, b: e.b, facing: .down, owner: owner, rim: l.kind == .screenBorder, box: box))
            }
        }
        let lidEdge = lid + off

        /// What is over (x, y), near enough to keep the rain off: how high
        /// above its body, and whose it is. (The lid of the tank only right
        /// under it.)
        func roof(_ x: CGFloat, _ y: CGFloat) -> (h: CGFloat, owner: Int, lid: Bool)? {
            var best: (h: CGFloat, owner: Int, lid: Bool)?
            for i in roofCols[col(x)] ?? [] {
                let s = roofs[i]
                guard x >= s.box.minX, x < s.box.maxX else { continue }
                let hh = yAt(s, x) - y
                guard hh > 4, hh < 320 * sc else { continue }
                let lid = s.rim && s.owner == 0 && s.box.minY >= lidEdge - 2
                if lid, hh > 60 * sc { continue }
                if hh < best?.h ?? .greatestFiniteMagnitude { best = (hh, s.owner, lid) }
            }
            return best
        }
        /// The nearest wall to one side of `p`, at its height: how far, whose,
        /// and whether it is the glass.
        func wall(_ p: V2, _ dir: CGFloat) -> (d: CGFloat, owner: Int, glass: Bool)? {
            var best: (d: CGFloat, owner: Int, glass: Bool)?
            for i in (dir > 0 ? lefts : rights)[col(p.y)] ?? [] {
                let s = segs[i]
                guard p.y >= s.box.minY - 2, p.y <= s.box.maxY + 2 else { continue }
                let x = abs(s.b.y - s.a.y) > 0.01 ? s.a.x + (s.b.x - s.a.x) * (p.y - s.a.y) / (s.b.y - s.a.y) : (s.box.minX + s.box.maxX) / 2
                let d = (x - p.x) * dir
                guard d > -3, d < 150 * sc else { continue }
                if d < best?.d ?? .greatestFiniteMagnitude { best = (max(d, 0), s.owner, s.rim && s.owner == 0) }
            }
            return best
        }
        /// How far a look from `o` along `d` gets before something is in the
        /// way: square by square along it, as far as it gets.
        var seen = [Int](repeating: -1, count: segs.count), stamp = 0
        func sight(_ o: V2, _ d: V2, _ len: CGFloat) -> CGFloat {
            stamp += 1
            var best = len
            var cx = Int((o.x / cellSide).rounded(.down)), cy = Int((o.y / cellSide).rounded(.down))
            let sx = d.x > 0 ? 1 : -1, sy = d.y > 0 ? 1 : -1
            var nx = abs(d.x) > 1e-9 ? (CGFloat(cx + (sx > 0 ? 1 : 0)) * cellSide - o.x) / d.x : .greatestFiniteMagnitude
            var ny = abs(d.y) > 1e-9 ? (CGFloat(cy + (sy > 0 ? 1 : 0)) * cellSide - o.y) / d.y : .greatestFiniteMagnitude
            let stepX = abs(d.x) > 1e-9 ? cellSide / abs(d.x) : .greatestFiniteMagnitude
            let stepY = abs(d.y) > 1e-9 ? cellSide / abs(d.y) : .greatestFiniteMagnitude
            var enter: CGFloat = 0
            while enter <= best {
                for i in cells[cellKey(cx, cy)] ?? [] where seen[i] != stamp {
                    seen[i] = stamp
                    let s = segs[i]
                    let sd = s.b - s.a
                    let den = d.cross(sd)
                    guard abs(den) > 1e-9 else { continue }
                    let w = s.a - o
                    let u = w.cross(sd) / den, v = w.cross(d) / den
                    if u > 8, u < best, v >= 0, v <= 1 { best = u }
                }
                if nx < ny { enter = nx; nx += stepX; cx += sx } else { enter = ny; ny += stepY; cy += sy }
            }
            return best
        }
        func gap(_ r: CGRect, _ p: V2) -> CGFloat {
            V2(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY)).length
        }

        // What warms, what is damp, what draws prey.
        var warmers: [(CGRect, CGFloat)] = [], damp: [(CGRect, CGFloat)] = [], lures: [(CGRect, CGFloat)] = []
        for it in h.items where PlaceSurvey.counts(it) {
            let q = quals[it.id]!
            let w = max(q[.warm], q[.glowing] * 0.75)
            if w > 0.3 { warmers.append((it.rect, w)) }
            if q[.moistureSource] > 0.3 { damp.append((it.rect, q[.moistureSource])) }
            if q[.preyAttracting] > 0.3 { lures.append((it.rect, q[.preyAttracting])) }
        }

        // The places: first the named places on things…
        var out: [HabitatPlace] = []
        func cell(_ p: V2, in r: CGRect) -> String {
            let fx = clamp(Int(((p.x - r.minX) / max(r.width, 1) * 8).rounded(.down)), -3, 11)
            let fy = clamp(Int(((p.y - r.minY) / max(r.height, 1) * 8).rounded(.down)), -3, 11)
            return "\(fx).\(fy)"
        }
        var used = Set<String>()
        func unique(_ k: String) -> String {
            var key = k, n = 1
            while used.contains(key) { key = "\(k)~\(n)"; n += 1 }
            used.insert(key)
            return key
        }
        var waters: [Int: Water] = [:]
        for it in h.items where PlaceSurvey.counts(it) {
            for ip in it.interactionPoints(on: map, fromBeside: false) {
                guard let a = ip.stand, let sp = ip.standPoint, let seg = map.seg(a) else { continue }
                var pl = HabitatPlace(key: unique("\(it.uid):\(ip.kind.rawValue):\(cell(sp, in: it.rect))"), kind: ip.kind, anchor: a, point: sp,
                                      facing: seg.facing, owner: map.owner(of: a) ?? 0, thing: it.id)
                pl.focus = ip.point
                pl.along = ip.kind == .touch || ip.kind == .inspect ? ip.facing : ((ip.point - sp).dot(seg.dir) >= 0 ? 1 : -1)
                if ip.kind == .drinkEdge, let w = it.water {
                    // (Facing the water, and looking at the near side of it.)
                    let aim = V2(clamp(sp.x, w.minX + w.width * 0.2, w.maxX - w.width * 0.2), w.maxY - w.height * 0.3)
                    pl.focus = aim
                    pl.along = (aim - sp).dot(seg.dir) >= 0 ? 1 : -1
                    waters[it.id, default: Water(uid: it.uid, id: it.id, surface: w, drinks: [])].drinks.append(out.count)
                }
                out.append(pl)
            }
        }
        water = waters.values.sorted { $0.id < $1.id }
        // …then everywhere else on the surfaces, a spot to a patch.
        var named: [Int: [V2]] = [:]
        func bucket(_ p: V2) -> Int { Int((p.x / 40).rounded(.down)) &* 100_003 &+ Int((p.y / 40).rounded(.down)) }
        for pl in out { named[bucket(pl.point), default: []].append(pl.point) }
        func nearNamed(_ p: V2) -> Bool {
            for dx in -1...1 { for dy in -1...1 {
                let k = Int((p.x / 40).rounded(.down) + CGFloat(dx)) &* 100_003 &+ Int((p.y / 40).rounded(.down) + CGFloat(dy))
                if named[k]?.contains(where: { $0.distance(to: p) < 14 * sc }) == true { return true }
            } }
            return false
        }
        let glassBand = 34 * sc
        for s in HabitatItem.spots(on: map, in: world.insetBy(dx: -20, dy: -20), spacing: 24 * sc) {
            guard !nearNamed(s.point) else { continue }
            let owner = s.owner
            if owner != 0, let it = items[owner], !PlaceSurvey.counts(it) { continue }
            // Against the glass at an end of the tank: up the glass itself,
            // or on the floor — or on whatever is up against it — by it.
            let glass = (s.point.x < world.minX + off + glassBand || s.point.x > world.maxX - off - glassBand)
                && s.point.y < floor + 150 * sc && s.seg.facing != .down
            let key: String
            if owner != 0, let it = items[owner] {
                key = "\(it.uid):spot:\(cell(s.point, in: it.rect))"
            } else {
                key = "tank:\(Int((s.point.x / 32).rounded(.down))).\(Int((s.point.y / 32).rounded(.down))):\(s.seg.facing)"
            }
            guard !used.contains(key) else { continue }
            used.insert(key)
            var pl = HabitatPlace(key: key, kind: nil, glass: glass, anchor: s.anchor, point: s.point, facing: s.seg.facing, owner: owner, thing: owner)
            if glass { pl.along = (s.point.x < world.midX ? -1 : 1) * (s.seg.dir.x >= 0 ? 1 : -1) }
            out.append(pl)
        }

        // Shut doors: a spot on the floor either side, to go through from.
        for it in h.items where it.kind == .doorClosed {
            let r = it.rect
            var sides: [(anchor: Anchor, point: V2)] = []
            for side in [CGFloat(-1), 1] {
                let x = side < 0 ? r.minX - 30 * sc : r.maxX + 30 * sc
                if let s = HabitatItem.floor(below: V2(x, r.minY + 30 * sc), on: map, notOwnedBy: it.id), abs(s.point.y - (r.minY + off)) < 30 * sc {
                    sides.append(s)
                }
            }
            if !sides.isEmpty { doors.append(Door(id: it.id, rect: r, sides: sides)) }
        }

        // What each offers.
        for i in out.indices {
            var pl = out[i]
            let p = pl.point
            var q = PlaceQualities()
            var cov: CGFloat = 0, madeCov: CGFloat = 0, roofH = CGFloat.greatestFiniteMagnitude
            var overhead = false
            for dx in [-12 * sc, 0, 12 * sc] {
                guard let r = roof(p.x + dx, p.y) else { continue }
                // (The lid of the tank only at a pinch.)
                let c = r.lid ? 0.3 : clamp(1.2 - (r.h - off) / (280 * sc), 0.25, 1)
                cov += c / 3
                if built(r.owner) { madeCov += c / 3 }
                if r.h < roofH { roofH = r.h; pl.roofOwner = r.owner }
                if dx == 0 { overhead = true }
            }
            // (Right at the edge of a roof, with none straight over it, the
            // rain still gets it.)
            if !overhead { cov *= 0.3; madeCov *= 0.3 }
            if pl.hanging {
                // Under it: whatever it hangs from keeps the rain off — the
                // lid of the tank hardly (at a pinch).
                // (At the very end of an underside it slips round the
                // corner out from under it: only where it carries on either
                // side is it good cover.)
                let under = [-10 * sc, 10 * sc].allSatisfy { dx in roof(p.x + dx, p.y).map { $0.h < off * 1.8 } ?? false }
                let c: CGFloat = pl.owner == 0 ? 0.3 : (under ? 0.8 : 0.4)
                cov = max(cov, c)
                if built(pl.owner) { madeCov = max(madeCov, c) }
                pl.roofOwner = pl.owner
                roofH = 0
            }
            let wl = wall(p, -1), wr = wall(p, 1)
            func strength(_ w: (d: CGFloat, owner: Int, glass: Bool)?) -> CGFloat {
                w.map { clamp(1 - $0.d / (150 * sc), 0, 1) * ($0.glass ? 0.5 : 1) } ?? 0
            }
            let sl = strength(wl), sr = strength(wr)
            let madeWalls = (wl.map { built($0.owner) } == true ? sl : 0) + (wr.map { built($0.owner) } == true ? sr : 0)
            var enc = clamp(0.5 * cov + 0.25 * (sl + sr), 0, 1)
            if pl.kind == .interior { enc = max(enc, 0.95); cov = max(cov, 0.9) }
            // (In the mouth of it: shut in on most sides, but the rain gets in.)
            if pl.kind == .entrance { enc = max(enc, 0.55) }
            let elev = clamp((p.y - floor) / (300 * sc), 0, 1)
            let under = quals[pl.owner] ?? HabitatQualities()
            var made = clamp(0.85 * madeCov + 0.15 * min(madeWalls, 1) * min(cov * 2, 1), 0, 1)
            if built(pl.owner), pl.standing, under[.sleepingSuitable] >= 0.5 { made = max(made, 0.7) }
            q[.cover] = cov
            q[.enclosure] = enc
            q[.made] = made
            q[.shelter] = clamp(0.75 * cov + 0.35 * enc, 0, 1)
            q[.elevation] = elev
            q[.exposure] = clamp(1 - 0.85 * cov - 0.2 * enc + 0.15 * elev, 0, 1)
            var warm = under[.warm] * (pl.owner != 0 ? 1 : 0)
            for (r, w) in warmers { warm = max(warm, w * clamp(1 - gap(r, p) / (110 * sc), 0, 1)) }
            q[.warmth] = warm
            var wet = under[.wet] * (pl.owner != 0 ? 0.8 : 0)
            for (r, m) in damp { wet = max(wet, m * clamp(1 - gap(r, p) / (140 * sc), 0, 1)) }
            q[.moisture] = wet
            q[.water] = pl.kind == .drinkEdge ? 1 : 0
            q[.silk] = max(pl.hanging ? 0.6 : 0, roofH < 90 * sc + off ? 0.45 : 0, under[.silkAnchor] * 0.8, pl.kind == .silkAnchor ? 1 : 0)
            var prey: CGFloat = 0
            for (r, v) in lures { prey = max(prey, v * clamp(1 - gap(r, p) / (220 * sc), 0, 1) * 0.7) }
            q[.preyActivity] = prey
            q[.access] = walkable.contains(pl.anchor.loopID) ? 1 : 0.35
            let lie: CGFloat = pl.standing ? 1 : (pl.hanging ? 0.8 : 0.35)
            q[.rest] = clamp(lie * (0.5 + 0.3 * cov + 0.2 * enc) + 0.3 * under[.sleepingSuitable] + (pl.kind == .interior ? 0.15 : 0), 0, 1)
            q[.safety] = clamp(0.4 * enc + 0.35 * cov + 0.25 * (1 - q[.exposure]), 0, 1)
            q[.novelty] = clamp(quals[pl.thing]?[.interesting] ?? 0.2, 0, 1)
            // Facing out of a shelter: away from the nearer wall.
            if pl.kind == nil, !pl.glass, cov > 0.3, let seg = map.seg(pl.anchor), abs(seg.dir.x) > 0.5 {
                let dl = wl?.d ?? .greatestFiniteMagnitude, dr = wr?.d ?? .greatestFiniteMagnitude
                let out: CGFloat = dl < dr ? 1 : -1
                pl.along = out * (seg.dir.x >= 0 ? 1 : -1)
            }
            pl.q = q
            out[i] = pl
        }

        // How far each high place sees: a fan of looks from it.
        let reach = 600 * sc
        for i in out.indices {
            var pl = out[i]
            // (Only somewhere up high it could sit and look out from: the
            // rest only see about as far as they are open and up.)
            let high = pl.q[.elevation] > 0.2 && pl.standing
            let named = pl.kind == .top || pl.kind == .perch || pl.kind == .lookout
            guard high || named else {
                pl.q[.visibility] = clamp(0.25 * (1 - pl.q[.enclosure]) + 0.3 * pl.q[.elevation], 0, 1)
                pl.q[.hunting] = clamp(0.35 * pl.q[.visibility] + 0.45 * pl.q[.preyActivity] + 0.25 * (quals[pl.owner]?[.huntingSuitable] ?? 0), 0, 1)
                out[i] = pl
                continue
            }
            let n = pl.facing.normal
            let o = pl.point + n * 3
            var free: CGFloat = 0, best: (len: CGFloat, dir: V2)?
            for k in 0..<12 {
                let a = (-110 + CGFloat(k) * 20) * .pi / 180
                let d = n.rotated(by: a)
                let l = sight(o, d, reach)
                free += l / reach / 12
                // (Over the tank, not up at the lid: a look outward and down.)
                if d.y < 0.5, l > best?.len ?? 0 { best = (l, d) }
            }
            pl.q[.visibility] = clamp(0.6 * free + 0.4 * pl.q[.elevation], 0, 1)
            pl.q[.hunting] = clamp(0.35 * pl.q[.visibility] + 0.2 * pl.q[.elevation] + 0.45 * pl.q[.preyActivity]
                                   + 0.25 * (quals[pl.owner]?[.huntingSuitable] ?? 0), 0, 1)
            if let b = best, pl.kind != .drinkEdge {
                let view = pl.point + b.dir * b.len * 0.8
                pl.focus = view
                if let seg = map.seg(pl.anchor) { pl.along = (view - pl.point).dot(seg.dir) >= 0 ? 1 : -1 }
            }
            out[i] = pl
        }

        places = out
        for (i, pl) in places.enumerated() { byKey[pl.key] = i }
    }

    func place(_ key: String) -> HabitatPlace? { byKey[key].map { places[$0] } }

    /// The place nearest `p`, within `within`.
    func nearest(to p: V2, within: CGFloat) -> HabitatPlace? {
        var best: (d: CGFloat, i: Int)?
        for (i, pl) in places.enumerated() {
            let d = pl.point.distance(to: p)
            if d < within, d < best?.d ?? .greatestFiniteMagnitude { best = (d, i) }
        }
        return best.map { places[$0.i] }
    }

    // MARK: Choosing

    /// Everything a place offers, as it seems to it now: what it is (as
    /// laid out), and what it has made of it and what is going on there —
    /// how well it knows it, how new it still is, how much goes on there
    /// to trouble it, how safe it is all told, how much prey comes by.
    func sensed(_ pl: HabitatPlace, _ sense: PlaceSense) -> PlaceQualities {
        var q = pl.q
        let r = sense.record
        let fam = r.map { 1 - exp(-$0.visits / 4) } ?? 0
        let disturb = clamp(sense.disturbance + min(r?.frights ?? 0, 1) * 0.7, 0, 1)
        q[.familiarity] = fam
        q[.novelty] = clamp(pl.q[.novelty] * (1 - fam) + (r == nil ? 0.3 : 0), 0, 1)
        q[.disturbance] = disturb
        q[.safety] = clamp(pl.q[.safety] * 0.75 + fam * 0.25 - disturb * 0.6, 0, 1)
        q[.preyActivity] = clamp(pl.q[.preyActivity] + (r?.catches ?? 0) * 0.35 + (r?.sightings ?? 0) * 0.15 + sense.prey * 0.6, 0, 1)
        if pl.standing { q[.warmth] = max(q[.warmth], min(1, sense.warm * 1.1)) }
        return q
    }

    /// How good a place is for what it has in mind, all told (0: no good
    /// for it at all): all it offers (`sensed`), weighed for the use, and
    /// how far off it is.
    func appeal(_ pl: HabitatPlace, _ want: PlaceWant, _ sense: PlaceSense) -> CGFloat {
        let q = sensed(pl, sense)
        let sc = want.scale
        let P = want.personality
        let r = sense.record
        let fam = q[.familiarity]
        let fond = r?.fond[want.use.rawValue] ?? 0
        let disturb = q[.disturbance]
        let safety = q[.safety]
        let d = pl.point.distance(to: want.from)
        func far(_ k: CGFloat) -> CGFloat { 1 / (1 + d / (k * sc)) }
        let made = q[.made]
        var s: CGFloat
        switch want.use {
        case .shelter:
            guard q[.cover] >= 0.35 else { return 0 }
            // (Cover the keeper built first: see the top of the file.)
            s = 1.2 * q[.cover] + 0.5 * q[.enclosure] + 1.6 * made + 0.3 * fam + 0.6 * fond + 0.2 * q[.access] - 0.3 * q[.exposure] - 0.4 * disturb
            s *= far(700)
        case .hide:
            guard q[.enclosure] >= 0.3 || q[.cover] >= 0.55 else { return 0 }
            s = 1.0 * q[.enclosure] + 0.6 * q[.cover] + 1.6 * made + 0.5 * safety + 0.5 * fond + 0.3 * fam - 0.6 * disturb
            if let th = want.threat {
                let away = pl.point.distance(to: th)
                s += 0.4 * clamp(away / (400 * sc), 0, 1) - (away < 90 * sc ? 0.9 : 0)
            }
            s *= far(550)
        case .sleep:
            // Not out in the open up a wall.
            guard pl.facing == .up || pl.facing == .down || q[.enclosure] > 0.6 else { return 0 }
            s = 0.8 * q[.rest] + 0.45 * q[.cover] + 0.35 * q[.enclosure] + 1.4 * made + 0.5 * safety + 0.5 * fam + 1.4 * fond - 0.8 * disturb
                // (The bold like it high; the timid low and tucked in.)
                + (P.bravery - 0.5) * 0.5 * q[.elevation]
            if want.rough { s -= 0.5 * q[.exposure] }
            s *= far(1500)
        case .rest:
            s = 0.7 * q[.rest] + 0.25 * q[.cover] + 0.2 * q[.enclosure] + 0.8 * made + 0.25 * q[.warmth] + 0.3 * safety + 0.35 * fam + 1.3 * fond - 0.6 * disturb
            s *= far(800)
        case .lookout:
            guard q[.elevation] >= 0.25, pl.standing else { return 0 }
            s = 1.0 * q[.elevation] + 1.1 * q[.visibility] + 0.3 * fam + 1.2 * fond - 0.3 * q[.cover] - 0.4 * disturb + (pl.kind == .lookout ? 0.3 : 0)
            s *= far(1100)
        case .drink:
            guard q[.water] >= 0.9 else { return 0 }
            s = 1 + 0.4 * fam + 0.8 * fond + 0.3 * q[.access] - 0.5 * disturb
            s *= far(900)
        case .hunt:
            let prey = q[.preyActivity]
            guard prey > 0.15, pl.facing != .down else { return 0 }
            s = 1.0 * prey + 0.35 * q[.hunting] + 0.25 * q[.visibility] + 0.2 * q[.elevation] + 0.8 * fond - 0.3 * disturb
            s *= far(900)
        case .bask:
            // Something warm by it, or the sun on an open top.
            let warm = max(q[.warmth], pl.standing ? want.sun * q[.exposure] * 0.8 : 0)
            guard warm >= 0.3 else { return 0 }
            s = 1.2 * warm + 0.3 * fam + 0.7 * fond - 0.3 * disturb
            s *= far(900)
        case .perch:
            guard pl.owner != 0, pl.standing, q[.elevation] > 0.05 else { return 0 }
            s = 0.4 * q[.elevation] + 0.3 * q[.visibility] + 0.3 * q[.rest] + 1.3 * fond + 1.0 * max(sense.thingFond, 0) + 0.3 * fam - 0.6 * disturb
            s *= far(1000)
        }
        return max(s, 0)
    }

    /// The best places for `want` that it knows of (`sense` nil: it doesn't
    /// know it is there), best first, with how good each is.
    func ranked(_ want: PlaceWant, top: Int = 8, sense: (HabitatPlace) -> PlaceSense?) -> [(place: HabitatPlace, score: CGFloat)] {
        var out: [(place: HabitatPlace, score: CGFloat)] = []
        for pl in places {
            guard let s = sense(pl) else { continue }
            let a = appeal(pl, want, s)
            if a > 0.05 { out.append((pl, a)) }
        }
        out.sort { $0.score > $1.score }
        return Array(out.prefix(top))
    }
}

/// Where two surfaces meet, as its memory of the way knows it: by where it
/// is, to within a few points (a thing moved is a new way).
func routeKey(_ j: SurfaceJunction) -> String {
    "\(Int((j.at.x / 8).rounded())).\(Int((j.at.y / 8).rounded()))"
}
