import CoreGraphics
import Foundation

// MARK: - The tank as a living place
//
// The things in the tank, the creatures that come to it and the weather
// over it, as one world rather than three.
//
// • What is open to the sky (`SkyCover`): worked out from the solid shapes
//   of things, so rain wets and snow lies only where nothing is over it, a
//   plant in under a roof hardly stirs in a gale, and a creature caught out
//   in a shower knows where to get in out of it.
// • What draws what (`EcoSite`): flowers draw flies and moths; water,
//   mosquitoes; leaf litter, beetles, worms and ants; bark and logs, beetles
//   and ants, and somewhere to hide; plants, ladybugs; a dark shelter,
//   crickets; the damp, worms; a light after dark, moths. All from what each
//   thing is — what its definition says it is made of, what it is for,
//   where it grows — never from what it is called. None of it makes anything
//   appear: it only tips the odds of what finds its way in, and where
//   (`arrivalOdds`, `arrival`), and where whatever is in there goes: to land,
//   to rest, to hide, to wait out the rain (`haunt`).
// • What the weather leaves on things: rain beaded on the leaves for a
//   while after a shower (`droplets`), drying off quicker in the sun and the
//   wind; stone warmed through by the sun, warm a while after; and what is
//   left of a meal, until the ants have it (`remains`).
//
// The scene keeps one of these for the tank and keeps it up with the weather
// (HabitatScene.swift); the spider, and whatever is loose in the tank, read
// it. Nothing here is ever shown as a number: it only shows in what goes on.

// MARK: - Open to the sky

/// What is over each part of the tank near enough to keep the rain and the
/// snow off it: the solid shapes of things, column by column across the
/// world. (The lid of the tank keeps nothing off: the weather is in there.)
struct SkyCover {
    /// Something solid across a column: its underside, its top, whose it is.
    struct Span { var bottom: CGFloat; var top: CGFloat; var owner: Int }
    let step: CGFloat
    private(set) var cols: [[Span]]
    /// How far above something a roof still keeps the weather off it.
    static let reach: CGFloat = 320

    /// Whether a thing keeps weather off what is under it: not the back wall
    /// and its hardware, not what lies flat on the ground, not what hangs.
    static func shelters(_ it: HabitatItem) -> Bool {
        PlaceSurvey.counts(it) && it.kind.definition.shelf != .ground && !it.inFront
            && (!it.kind.hangs || it.kind.functions.contains(.cover) || it.kind.functions.contains(.retreat))
    }

    /// Which parts of it do. (The tank is seen side on: a branch across it
    /// is only as deep as it is thick, and the rain falls past it in front
    /// and behind; a table top, a floor, a stone, a log, a leaf is a roof.)
    /// Whatever it is meant for shelter, all of it; anything with a body to
    /// it (the top of a table, a stone), that; the leaves of a plant, the
    /// broad ones that lie across; not branches, vines, stems, posts, rope.
    static func roofs(_ part: ShapePart, of it: HabitatItem) -> Bool {
        let d = it.kind.definition
        if d.traits.functions.contains(.cover) || d.traits.functions.contains(.retreat) || part.role == .bulk { return true }
        guard d.shelf == .plants, [.leaf, .moss].contains(d.traits.material) else { return false }
        let b = Poly.bounds(part.outline)
        return b.width > b.height * 0.8
    }

    init(_ h: Habitat, step: CGFloat = 6) {
        self.step = step
        let n = max(1, Int((h.size.width / step).rounded(.up)) + 1)
        var cols = [[Span]](repeating: [], count: n)
        for it in h.items where SkyCover.shelters(it) {
            for part in it.geometry.parts where SkyCover.roofs(part, of: it) {
                let o = part.outline
                guard o.count >= 3 else { continue }
                let b = Poly.bounds(o)
                let c0 = max(0, Int((b.minX / step).rounded(.up))), c1 = min(n - 1, Int((b.maxX / step).rounded(.down)))
                guard c0 <= c1 else { continue }
                for c in c0...c1 {
                    let x = CGFloat(c) * step
                    var ys: [CGFloat] = []
                    for i in o.indices {
                        let a = o[i], e = o[(i + 1) % o.count]
                        guard (a.x <= x) != (e.x <= x) else { continue }
                        ys.append(a.y + (e.y - a.y) * (x - a.x) / (e.x - a.x))
                    }
                    guard ys.count >= 2 else { continue }
                    ys.sort()
                    var k = 0
                    while k + 1 < ys.count {
                        cols[c].append(Span(bottom: ys[k], top: ys[k + 1], owner: it.id))
                        k += 2
                    }
                }
            }
        }
        for c in cols.indices where cols[c].count > 1 { cols[c].sort { $0.bottom < $1.bottom } }
        self.cols = cols
    }

    private func column(_ x: CGFloat) -> Int? {
        let c = Int((x / step).rounded())
        return cols.indices.contains(c) ? c : nil
    }

    /// The nearest underside over `p` — not touching it, and near enough to
    /// keep the weather off (`reach`) — and whose it is (anything but
    /// `ignoring`'s).
    func roof(over p: V2, reach: CGFloat = SkyCover.reach, ignoring: Int? = nil) -> (y: CGFloat, owner: Int)? {
        guard let c = column(p.x) else { return nil }
        for s in cols[c] where s.bottom > p.y + 4 && s.owner != ignoring {
            return s.bottom - p.y < reach ? (s.bottom, s.owner) : nil
        }
        return nil
    }

    /// How open to the sky `p` is: 1 nothing over it, 0 roofed right over
    /// (over a little width, so the very edge of a roof is half and half).
    func open(at p: V2, reach: CGFloat = SkyCover.reach, ignoring: Int? = nil) -> CGFloat {
        var n: CGFloat = 0
        for dx in [-8, 0, 8] as [CGFloat] where roof(over: V2(p.x + dx, p.y), reach: reach, ignoring: ignoring) == nil { n += 1 }
        return n / 3
    }

    /// The stretches across the tank, at height `y`, with something over
    /// them (at least `minWidth` wide): where the floor stays dry.
    func covered(at y: CGFloat, minWidth: CGFloat = 10) -> [(lo: CGFloat, hi: CGFloat, owner: Int)] {
        var out: [(lo: CGFloat, hi: CGFloat, owner: Int)] = []
        var run: (lo: CGFloat, owner: Int)?
        for c in cols.indices {
            let x = CGFloat(c) * step
            if let r = roof(over: V2(x, y)) {
                if run == nil { run = (x, r.owner) }
            } else if let r = run {
                if x - step - r.lo >= minWidth { out.append((r.lo, x - step, r.owner)) }
                run = nil
            }
        }
        if let r = run, CGFloat(cols.count - 1) * step - r.lo >= minWidth { out.append((r.lo, CGFloat(cols.count - 1) * step, r.owner)) }
        return out
    }
}

// MARK: - What draws what

/// Something about a thing that draws creatures.
enum EcoFeature: String, CaseIterable {
    /// Flowers.
    case bloom
    /// Open water.
    case water
    /// Leaf litter: fallen leaves, needles, twigs.
    case litter
    /// Bark and logs, roots and stumps.
    case bark
    /// Leafy plants and vines.
    case foliage
    /// Somewhere shut in and shady: a cave, a den, a hollow, a room.
    case dark
    /// Damp: moss, the wet ground by water.
    case damp
    /// A light — after dark.
    case glow
    /// Toadstools and fungus.
    case fungus
    /// Food put out.
    case food
    /// What is left of a meal.
    case remains

    /// How much it draws each kind of creature, by itself (at full strength).
    func pull(_ k: PreyKind, night: Bool) -> CGFloat {
        switch (self, k) {
        case (.bloom, .fruitFly): return 2.4
        case (.bloom, .moth): return night ? 2.2 : 1.0
        case (.bloom, .ladybug): return 0.4
        case (.bloom, .mosquito): return 0.2
        case (.bloom, .beetle): return 0.2
        case (.water, .mosquito): return 2.6
        case (.water, .fruitFly): return 0.5
        case (.water, .moth): return 0.2
        case (.litter, .beetle): return 1.6
        case (.litter, .worm): return 1.6
        case (.litter, .ant): return 2.0
        case (.litter, .cricket): return 0.6
        case (.bark, .beetle): return 2.0
        case (.bark, .ant): return 2.0
        case (.bark, .cricket): return 0.5
        case (.bark, .moth): return night ? 0.2 : 0.5
        case (.foliage, .ladybug): return 1.8
        case (.foliage, .fruitFly): return 0.6
        case (.foliage, .moth): return 0.5
        case (.foliage, .mosquito): return 0.3
        case (.foliage, .cricket): return 0.3
        case (.dark, .cricket): return 1.9
        case (.dark, .beetle): return 0.8
        case (.dark, .ant): return 0.3
        case (.damp, .worm): return 2.0
        case (.damp, .mosquito): return 0.7
        case (.damp, .cricket): return 0.35
        case (.damp, .fruitFly): return 0.3
        case (.glow, .moth): return night ? 3.2 : 0.1
        case (.glow, .mosquito): return night ? 0.6 : 0
        case (.glow, .fruitFly): return night ? 0.3 : 0
        case (.fungus, .fruitFly): return 1.3
        case (.fungus, .beetle): return 0.6
        case (.fungus, .worm): return 0.3
        case (.food, .fruitFly): return 1.6
        case (.food, .cricket): return 0.8
        case (.remains, .ant): return 3.0
        case (.remains, .fruitFly): return 0.9
        default: return 0
        }
    }

    /// A creature there, keeping still, is hard to see.
    var hides: Bool { [.litter, .bark, .dark].contains(self) }
}

/// Something in the tank that draws creatures, and what of it they use.
struct EcoSite {
    var feature: EcoFeature
    /// The thing (its `id`), or 0: a room under a roof, what is left of a meal.
    var thing: Int
    var rect: CGRect
    /// 0…1-ish: how much of it there is.
    var strength: CGFloat
    /// Spots on the surfaces (by index into `HabitatEcology.spots`): on it,
    /// and on the ground by it or under it.
    var on: [Int] = []
    var by: [Int] = []
}

/// A spot on the tank's surfaces, as a creature sees it.
struct EcoSpot {
    var anchor: Anchor
    /// The body line there (see `SurfaceLoop`), and the surface itself.
    var point: V2
    var surface: V2
    var normal: V2
    var facing: EdgeFacing
    /// Whose surface it is (0: the tank's).
    var owner: Int
    /// Open to the sky, 0…1 — and, roofed over, well in under it (roofed a
    /// body's length either side too).
    var open: CGFloat
    var deep = false
    /// How far above the floor.
    var height: CGFloat
}

/// A drop of rain beaded on a leaf.
struct Droplet {
    var id: Int
    /// The thing it is on.
    var thing: Int
    /// On the leaf's top, in the world.
    var p: V2
    var r: CGFloat
    /// It can be got at from the surfaces (not only drawn on foliage).
    var reachable: Bool
}

/// What is left of a meal.
struct Remains {
    var id: Int
    var kind: PreyKind
    var p: V2
    var angle: CGFloat
    var age: CGFloat = 0
    var life: CGFloat
    /// Being carried off (by the creature with this id), and how long since
    /// it was last moved (gone out of the tank with it, say: put down).
    var carrier: Int?
    var unmoved: CGFloat = 0
    var alpha: CGFloat { clamp((life - age) / 20, 0, 1) }
}

/// Where something loose in the tank is off to, and what for.
enum Haunt {
    /// Somewhere to land (something with wings), on what draws it.
    case land
    /// Somewhere to settle a long while, up off the ground.
    case rest
    /// Out of sight: under bark, in the litter, in the dark.
    case hide
    /// Out of the rain.
    case shelter
}

/// How a creature finds its way in: out from under something on the
/// surfaces, or in on the wing to what drew it.
struct EcoArrival {
    var kind: PreyKind
    /// What drew it (`HabitatEcology.sites`), if anything.
    var site: Int?
    var feature: EcoFeature?
    /// Where it shows: a walker comes out onto `anchor`; a flier comes down
    /// through the air at `at`.
    var at: V2
    var anchor: Anchor?
    var dir: CGFloat = 1
    /// A little line of them (ants).
    var count = 1
    /// The patch a flier keeps to.
    var patch: CGRect
    /// A flier's first landing: somewhere on what drew it.
    var land: EcoSpot?
}

extension PreyKind {
    /// Something is left of it after a meal (the same as `LeftoverArt` draws).
    var leavesRemains: Bool { [.fruitFly, .moth, .mosquito, .beetle, .cricket].contains(self) }
}

// MARK: - The ecology

final class HabitatEcology {
    private(set) var sky = SkyCover(Habitat())
    private(set) var sites: [EcoSite] = []
    private(set) var spots: [EcoSpot] = []
    private(set) var world = CGRect(x: 0, y: 0, width: HabitatLayout.width, height: HabitatLayout.height)
    /// The body's height standing on the floor.
    private(set) var floor: CGFloat = HabitatLayout.ground + 22
    private(set) var standoff: CGFloat = 22
    /// Spots filed by column, for looking up what is near.
    private var spotCols: [Int: [Int]] = [:]
    private let band: CGFloat = 64
    private var items: [Int: HabitatItem] = [:]

    /// The weather as it is in the tank, and whether it is dark out.
    private(set) var weather = WeatherFeel.calm
    var night = false
    /// Seconds since it last rained properly (very large: not for ages).
    private(set) var sinceRain: CGFloat = 99_999
    /// How hard it has been raining, lately (eased).
    private(set) var wetness: CGFloat = 0

    /// Rain on the leaves.
    private(set) var droplets: [Droplet] = []
    /// Where drops can bead: along the tops of leafy things, open to the sky.
    private var wetSpots: [(thing: Int, p: V2, reachable: Bool)] = []
    private var dropBudget: CGFloat = 0
    private var nextID = 1
    /// Changed, thing by thing, for the scene to draw them again.
    private(set) var dropVersion: [Int: Int] = [:]

    /// Stone warmed through in the sun (by thing `id`), 0…1.
    private(set) var warmth: [Int: CGFloat] = [:]
    /// Things that hold the sun's warmth, and how open to the sun they are.
    private var stones: [Int: CGFloat] = [:]

    private(set) var remains: [Remains] = []
    private(set) var remainsVersion = 0

    init() {}

    // MARK: Laying out

    /// The tank as it is laid out now, on its surfaces. What was on things
    /// that are still where they were (drops, warmth) is kept.
    func relayout(_ h: Habitat, map: SurfaceMap) {
        let old = items
        items = Dictionary(h.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        world = CGRect(origin: .zero, size: h.size)
        standoff = map.standoff
        floor = HabitatLayout.ground + map.standoff
        sky = SkyCover(h)

        // Every spot on the surfaces, a few to each thing.
        spots = []
        spotCols = [:]
        for s in HabitatItem.spots(on: map, in: world.insetBy(dx: -10, dy: -10), spacing: 12) {
            if s.owner != 0, let it = items[s.owner], !PlaceSurvey.counts(it) { continue }
            let n = s.seg.dir.perp
            var e = EcoSpot(anchor: s.anchor, point: s.point, surface: s.point - n * map.standoff, normal: n, facing: s.seg.facing,
                            owner: s.owner, open: sky.open(at: s.point), height: s.point.y - floor)
            e.deep = e.open == 0 && sky.roof(over: s.point + V2(-20, 0)) != nil && sky.roof(over: s.point + V2(20, 0)) != nil
            spotCols[Int((s.point.x / band).rounded(.down)), default: []].append(spots.count)
            spots.append(e)
        }

        // What draws what.
        sites = []
        for it in h.items where PlaceSurvey.counts(it) {
            for (f, s) in HabitatEcology.features(of: it) {
                var site = EcoSite(feature: f, thing: it.id, rect: it.rect, strength: s)
                fill(&site)
                sites.append(site)
            }
        }
        // A room under a built roof is somewhere dark too.
        for c in sky.covered(at: floor, minWidth: 60) {
            guard let roofOwner = items[c.owner], roofOwner.kind.builtForIt else { continue }
            var site = EcoSite(feature: .dark, thing: 0, rect: CGRect(x: c.lo, y: HabitatLayout.ground, width: c.hi - c.lo, height: 120), strength: 0.5)
            fill(&site)
            sites.append(site)
        }
        for r in remains { addRemainsSite(r) }

        // Where rain beads: along the tops of what is leafy, open to it.
        wetSpots = []
        for it in h.items where PlaceSurvey.counts(it) && HabitatEcology.holdsDrops(it) {
            let g = it.geometry
            for (polys, reach) in [(g.parts.map(\.outline), true), (g.visual, false)] {
                for line in HabitatEcology.tops(of: polys, step: 6) {
                    for i in line.indices {
                        let p = line[i]
                        // (Not where it is too steep for one to cling: it runs off.)
                        let a = line[max(i - 1, 0)], b = line[min(i + 1, line.count - 1)]
                        guard abs(b.y - a.y) <= abs(b.x - a.x) * 2.4 + 0.5 else { continue }
                        guard sky.open(at: p + V2(0, 3)) > 0.5 else { continue }
                        wetSpots.append((it.id, p, reach))
                    }
                }
            }
        }
        // Drops on what hasn't moved stay.
        let before = droplets
        droplets = before.filter { d in items[d.thing].map { it in old[d.thing].map { $0.rect == it.rect } ?? false } ?? false }
        for d in before where !droplets.contains(where: { $0.id == d.id }) { bump(d.thing) }

        // What holds the sun's warmth.
        stones = [:]
        for it in h.items where PlaceSurvey.counts(it) {
            let m = it.kind.definition.traits.material
            let holds: CGFloat = it.kind.functions.contains(.basking) ? 1 : [.stone, .crystal].contains(m) ? 0.85
                : [.wood, .driftwood, .bark].contains(m) && it.kind.definition.category == .perch ? 0.35 : 0
            guard holds > 0 else { continue }
            let top = V2(it.rect.midX, it.rect.maxY + 4)
            stones[it.id] = holds * sky.open(at: top)
        }
        warmth = warmth.filter { stones[$0.key] != nil }
    }

    /// Its spots: on the thing, and on the ground by it or under it.
    private func fill(_ site: inout EcoSite) {
        let r = site.rect
        let around = r.insetBy(dx: -50, dy: -30)
        for i in near(around) {
            let s = spots[i]
            if site.thing != 0, s.owner == site.thing {
                site.on.append(i)
            } else if s.owner != site.thing, around.contains(s.point.point), s.point.y < r.minY + max(r.height * 0.5, 40) {
                site.by.append(i)
            }
        }
    }

    /// Spot indices within `r`.
    private func near(_ r: CGRect) -> [Int] {
        var out: [Int] = []
        let c0 = Int((r.minX / band).rounded(.down)), c1 = Int((r.maxX / band).rounded(.down))
        guard c0 <= c1 else { return [] }
        for c in c0...c1 {
            for i in spotCols[c] ?? [] where r.contains(spots[i].point.point) { out.append(i) }
        }
        return out
    }

    /// Everything about a thing that draws creatures, and how much of it.
    static func features(of it: HabitatItem) -> [(EcoFeature, CGFloat)] {
        let d = it.kind.definition, tr = d.traits, m = tr.material, fn = tr.functions
        let nature = it.kind.nature
        // (Bigger things count for more, up to a point.)
        let size = clamp(sqrt(it.w * it.h) / 110, 0.45, 1.4)
        var out: [(EcoFeature, CGFloat)] = []
        func add(_ f: EcoFeature, _ s: CGFloat) { if s > 0.05 { out.append((f, min(s, 1.5))) } }
        let woody: Set<HabitatMaterial> = [.wood, .root, .driftwood]
        if d.group == .flowering { add(.bloom, 0.9 * size) }
        if fn.contains(.water) || m == .water { add(.water, 1.0 * size) }
        if (d.shelf == .ground && (m == .leaf || m == .wood)) || d.group == .leaves { add(.litter, (d.group == .leaves ? 0.6 : 1) * size) }
        if m == .bark {
            add(.bark, 1.0 * size)
        } else if woody.contains(m), d.shelf.natural {
            // (Down on the ground, a log or a root: up in the air, a branch
            // is bark to an ant, but little to a beetle.)
            let low = !it.kind.hangs && it.y < 30
            add(.bark, (low ? 0.9 : 0.35) * size)
        }
        if [.leaf, .stem, .moss].contains(m), d.shelf == .plants || d.group == .vines || d.group == .climbers || d.shelf == .shelter {
            add(.foliage, (d.group == .succulents ? 0.35 : d.shelf == .shelter ? 0.5 : 0.85) * size)
        }
        if fn.contains(.retreat) || nature[.enclosed] >= 0.85 { add(.dark, 1.0) } else if fn.contains(.cover) { add(.dark, 0.45) }
        let wet = nature[.moistureSource]
        if !fn.contains(.water), m != .water, wet > 0.3 { add(.damp, wet) } else if fn.contains(.water) || m == .water { add(.damp, 0.6) }
        if nature[.glowing] > 0.3 { add(.glow, nature[.glowing]) }
        if m == .fungus { add(.fungus, 0.8 * size) }
        if fn.contains(.feeding) || (tr.extra[.preyAttracting] ?? 0) >= 0.9 { add(.food, 1) }
        return out
    }

    /// Leafy — or soft and damp — enough for rain to bead on.
    static func holdsDrops(_ it: HabitatItem) -> Bool {
        let d = it.kind.definition, m = d.traits.material
        return [.leaf, .moss, .fungus, .stem].contains(m) && d.shelf != .ground && d.traits.loose == nil
    }

    /// The tops of `polys`, left to right, every `step` — one line to each
    /// stretch with something under it (see `ObjectGeometry.topLines`).
    static func tops(of polys: [[V2]], step: CGFloat) -> [[V2]] {
        var out: [[V2]] = []
        for o in polys where o.count >= 3 {
            let b = Poly.bounds(o)
            guard b.width > 2 else { continue }
            let n = max(2, Int(b.width / step))
            var line: [V2] = []
            for k in 0...n {
                let x = b.minX + b.width * CGFloat(k) / CGFloat(n)
                var top: CGFloat?
                for i in o.indices {
                    let a = o[i], e = o[(i + 1) % o.count]
                    guard (a.x <= x) != (e.x <= x) else { continue }
                    let y = a.y + (e.y - a.y) * (x - a.x) / (e.x - a.x)
                    if y > top ?? -.greatestFiniteMagnitude { top = y }
                }
                if let t = top { line.append(V2(x, t)) } else if line.count >= 2 { out.append(line); line = [] } else { line = [] }
            }
            if line.count >= 2 { out.append(line) }
        }
        return out
    }

    // MARK: The weather on things

    /// Time goes by, in this weather: rain beads on the leaves and dries off
    /// them, stone warms in the sun, what is left of meals goes.
    func update(_ w: WeatherFeel, dt: CGFloat) {
        weather = w
        wetness = approach(wetness, w.rain, 0.4, dt)
        if w.rain > 0.15 { sinceRain = 0 } else { sinceRain += dt }
        stepDrops(dt)
        stepWarmth(dt)
        stepRemains(dt)
    }

    private func bump(_ thing: Int) { dropVersion[thing, default: 0] += 1 }

    private func stepDrops(_ dt: CGFloat) {
        let w = weather
        let freezing = w.cold > 0.6 || w.snow > 0.1
        // Rain beads on the leaves (and a fog leaves a dew).
        let wetting = freezing ? 0 : max(w.rain, w.fog * 0.2)
        let most = min(wetSpots.count * 3 / 5, 200)
        if wetting > 0.03, !wetSpots.isEmpty {
            dropBudget += wetting * dt * CGFloat(wetSpots.count) * 0.03
            while dropBudget >= 1 {
                dropBudget -= 1
                guard droplets.count < most, let s = wetSpots.randomElement() else { dropBudget = 0; break }
                guard !droplets.contains(where: { $0.thing == s.thing && $0.p.distance(to: s.p) < 6 }) else { continue }
                droplets.append(Droplet(id: nextID, thing: s.thing, p: s.p, r: randRange(0.8, 1.3), reachable: s.reachable))
                nextID += 1
                bump(s.thing)
            }
        }
        guard !droplets.isEmpty else { return }
        // Growing in the rain until they run off; drying after — sooner in
        // the sun, the heat and the wind — and shaken off in the gusts.
        let dry = (1.0 / 420 + w.sun / 110 + w.heat / 80 + abs(w.wind) / 260) * (w.fog > 0.3 ? 0.4 : 1)
        let shake = max(0, abs(w.wind) - 0.55) * 0.12
        for i in droplets.indices.reversed() {
            var d = droplets[i]
            let was = d.r
            if wetting > 0.03 {
                d.r = min(d.r + wetting * dt * 0.05, w.fog > 0.3 && w.rain < 0.05 ? 1.4 : 2.6)
                if d.r >= 2.5, chance(dt * 0.25) { droplets.remove(at: i); bump(d.thing); continue }
            } else {
                d.r -= dry * dt * 1.4
            }
            if shake > 0, chance(shake * dt * (items[d.thing].map { $0.kind.definition.windLean * 8 + 0.2 } ?? 0.5)) {
                droplets.remove(at: i); bump(d.thing); continue
            }
            if d.r < 0.55 { droplets.remove(at: i); bump(d.thing); continue }
            droplets[i] = d
            if abs(d.r - was) > 0.12 || Int(d.r * 8) != Int(was * 8) { bump(d.thing) }
        }
    }

    /// Drops on thing `id`, for drawing.
    func droplets(on id: Int) -> [Droplet] { droplets.filter { $0.thing == id } }

    /// The drop nearest `p` it could get its mouth to, within `within`.
    func droplet(near p: V2, within: CGFloat, reachableOnly: Bool = true) -> Droplet? {
        var best: (d: CGFloat, x: Droplet)?
        for x in droplets where (!reachableOnly || x.reachable) && x.r > 0.9 {
            let d = x.p.distance(to: p)
            if d < within, d < best?.d ?? .greatestFiniteMagnitude { best = (d, x) }
        }
        return best?.x
    }

    func droplet(id: Int) -> Droplet? { droplets.first { $0.id == id } }

    /// Drunk from: smaller, and gone once there is nothing left of it.
    func sip(_ id: Int, by amount: CGFloat) {
        guard let i = droplets.firstIndex(where: { $0.id == id }) else { return }
        let was = droplets[i].r
        let now = was - amount
        let thing = droplets[i].thing
        if now < 0.5 {
            droplets.remove(at: i)
            bump(thing)
        } else {
            droplets[i].r = now
            if Int(now * 8) != Int(was * 8) { bump(thing) }
        }
    }

    /// Knocked off (a leg brushing it, a jolt): gone.
    func shed(_ id: Int) {
        guard let i = droplets.firstIndex(where: { $0.id == id }) else { return }
        bump(droplets[i].thing)
        droplets.remove(at: i)
    }

    private func stepWarmth(_ dt: CGFloat) {
        let w = weather
        for (id, open) in stones {
            var v = warmth[id] ?? 0
            let sun = w.sun * open
            if sun > 0.08 {
                // Soaking up the sun, slowly; the hotter the day the warmer.
                v += (min(1, sun * 0.9 + w.heat * 0.4) - v) * dt / 80
                warmth[id] = v
            } else if v > 0 {
                // Giving it back — quickly in the rain or the snow.
                v -= v * dt / (w.rain > 0.1 || w.snow > 0.1 ? 40 : 260)
                warmth[id] = v < 0.004 ? nil : v
            }
        }
    }

    // MARK: What is left of a meal

    /// What is left of a meal of `kind`, lying at `p` (on the surface).
    func leaveRemains(of kind: PreyKind, at p: V2, angle: CGFloat) {
        let r = Remains(id: nextID, kind: kind, p: p, angle: angle, life: randRange(240, 420))
        nextID += 1
        remains.append(r)
        if remains.count > 6 { remains.removeFirst() }
        addRemainsSite(r)
        remainsVersion += 1
    }

    private func addRemainsSite(_ r: Remains) {
        var site = EcoSite(feature: .remains, thing: -r.id, rect: CGRect(x: r.p.x - 12, y: r.p.y - 4, width: 24, height: 10), strength: 1)
        fill(&site)
        sites.append(site)
    }

    private func stepRemains(_ dt: CGFloat) {
        guard !remains.isEmpty else { return }
        var gone = false
        for i in remains.indices {
            remains[i].age += dt
            if remains[i].age >= remains[i].life { gone = true }
            if remains[i].carrier != nil {
                remains[i].unmoved += dt
                if remains[i].unmoved > 2 {
                    remains[i].carrier = nil
                    remainsVersion += 1
                }
            }
        }
        if gone {
            let ids = Set(remains.filter { $0.age >= $0.life }.map(\.id))
            remains.removeAll { ids.contains($0.id) }
            sites.removeAll { $0.feature == .remains && ids.contains(-$0.thing) }
            remainsVersion += 1
        }
    }

    /// The nearest of what is left of a meal, within `within`, that nothing
    /// else has.
    func remains(near p: V2, within: CGFloat) -> Remains? {
        remains.filter { $0.carrier == nil && $0.p.distance(to: p) < within }.min { $0.p.distance(to: p) < $1.p.distance(to: p) }
    }

    func remains(id: Int) -> Remains? { remains.first { $0.id == id } }

    /// Picked up by creature `by` (nil: put down), and wherever it is taken.
    func carry(_ id: Int, by: Int?, to p: V2? = nil) {
        guard let i = remains.firstIndex(where: { $0.id == id }) else { return }
        remains[i].carrier = by
        remains[i].unmoved = 0
        if let p { remains[i].p = p }
        if let s = sites.firstIndex(where: { $0.feature == .remains && $0.thing == -id }) {
            sites[s].rect = CGRect(x: remains[i].p.x - 12, y: remains[i].p.y - 4, width: 24, height: 10)
        }
        remainsVersion += 1
    }

    /// Taken away altogether (carried off out of the tank).
    func removeRemains(_ id: Int) {
        remains.removeAll { $0.id == id }
        sites.removeAll { $0.feature == .remains && $0.thing == -id }
        remainsVersion += 1
    }

    // MARK: What finds its way in

    /// Something coming down out of the sky hard enough to keep most things
    /// in: rain, snow, cold, wind, storm.
    private func weatherFactor(_ k: PreyKind) -> CGFloat {
        let w = weather
        var f: CGFloat = 1
        let flies = k.flies
        if w.rain > 0.2 { f *= k == .worm ? 3 : flies ? 0.3 : k == .ladybug ? 0.4 : k == .ant ? 0.6 : 0.85 }
        if w.rain <= 0.2, sinceRain < 600 { f *= k == .worm ? 2 : k == .mosquito ? 1.6 : k == .fruitFly ? 1.2 : 1 }
        if w.cold > 0.5 || w.snow > 0.2 { f *= flies ? 0.12 : 0.35 }
        if abs(w.wind) > 0.7 { f *= flies ? 0.4 : 0.8 }
        if w.sun > 0.4 || w.heat > 0.4 { f *= [.ant, .ladybug].contains(k) ? 1.35 : k == .fruitFly ? 1.2 : k == .worm ? 0.3 : k == .moth && !night ? 0.5 : 1 }
        if w.fog > 0.3 { f *= k == .mosquito ? 1.3 : k == .moth ? 1.2 : 1 }
        if w.storm > 0.3 || w.hail > 0.1 || w.sand > 0.3 { f *= 0.3 }
        return f
    }

    /// What of the tank draws `k` now: each site, weighed.
    private func pull(_ s: EcoSite, _ k: PreyKind) -> CGFloat { s.feature.pull(k, night: night) * s.strength }

    /// How likely each kind of creature is to be the next to find its way
    /// in, all told: a little of everything, and more of whatever the tank
    /// has what draws it — each kind's pull from all it likes there, with
    /// diminishing returns — by the hour and the weather.
    func arrivalOdds() -> [(kind: PreyKind, weight: CGFloat)] {
        let base: [PreyKind: CGFloat] = [
            .fruitFly: 0.8, .ant: 0.5, .beetle: 0.5, .moth: night ? 1.2 : 0.25, .mosquito: night ? 0.7 : 0.35,
            .ladybug: night ? 0.05 : 0.45, .cricket: night ? 0.8 : 0.25, .worm: 0.2,
        ]
        return PreyKind.allCases.map { k in
            let p = sites.reduce(CGFloat(0)) { $0 + pull($1, k) }
            let drawn = 4 * (1 - exp(-p / 4))
            return (k, (base[k]! + drawn) * weatherFactor(k))
        }
    }

    /// How lively the tank is, all told: how long, give or take, between one
    /// creature finding its way in and the next, in seconds. A bare tank
    /// hardly ever; one full of plants and litter and water, every few minutes.
    func arrivalGap() -> CGFloat {
        let rich = sites.reduce(CGFloat(0)) { $0 + $1.strength * ($1.feature == .remains ? 0.5 : 1) }
        let life = arrivalOdds().reduce(CGFloat(0)) { $0 + $1.weight } / 5.5
        return lerp(1200, 220, clamp(rich / 8, 0, 1)) / clamp(life, 0.35, 1.25) * randRange(0.6, 1.4)
    }

    /// The next creature to find its way in — drawn from the odds, and
    /// brought by what drew it, the nearer `near` (where it is watched from)
    /// the likelier. Nil: nowhere for it.
    func arrival(near p: V2, kind forced: PreyKind? = nil) -> EcoArrival? {
        let kind: PreyKind
        if let forced {
            kind = forced
        } else {
            let odds = arrivalOdds()
            var r = randRange(0, odds.reduce(0) { $0 + $1.weight })
            var pick = odds.last!.kind
            for o in odds {
                r -= o.weight
                if r <= 0 { pick = o.kind; break }
            }
            kind = pick
        }
        // What brought it: weighed by how much it draws this kind, and how
        // near it is to where it is watched from.
        var weights: [(Int, CGFloat)] = []
        for (i, s) in sites.enumerated() {
            let w = pull(s, kind)
            guard w > 0.05 else { continue }
            // (Mostly about where it is watched from: a tank this wide has
            // more going on in it than anyone sees at once.)
            let d = V2(s.rect.midX, s.rect.midY).distance(to: p)
            weights.append((i, w / (1 + (d / 750) * (d / 750))))
        }
        // (And now and then nothing in particular: in from nowhere.)
        let total = weights.reduce(0) { $0 + $1.1 }
        var site: Int?
        if total > 0, chance(total / (total + 0.35)) {
            var r = randRange(0, total)
            for (i, w) in weights {
                r -= w
                if r <= 0 { site = i; break }
            }
            site = site ?? weights.last?.0
        }
        return make(kind, site: site, near: p)
    }

    private func make(_ kind: PreyKind, site: Int?, near p: V2) -> EcoArrival? {
        let s = site.map { sites[$0] }
        let centre = s.map { V2($0.rect.midX, $0.rect.midY) } ?? p
        // (The patch of the tank a flier keeps to: round what drew it — up
        // to a light hung from the lid, if that is what it was.)
        let low = max(HabitatLayout.ground + 10, centre.y - 320)
        let patch = CGRect(x: centre.x - 380, y: low, width: 760, height: max(580, centre.y + 260 - low)).intersection(world.insetBy(dx: 30, dy: 30))
        if kind.flies {
            // In on the wing, from above what drew it.
            let land = s == nil ? nil : haunt(.land, for: kind, near: centre, within: 260, site: site)
            let at = V2(clamp(centre.x + randRange(-120, 120), world.minX + 40, world.maxX - 40),
                        min(max(centre.y, floor) + randRange(140, 260), world.maxY - 40))
            return EcoArrival(kind: kind, site: site, feature: s?.feature, at: at, patch: patch, land: land)
        }
        // A walker comes out from under it, or out of it, or out of the
        // litter; a ladybug, onto a leaf.
        var pool: [Int] = []
        if let s {
            switch s.feature {
            case .bark, .dark, .litter:
                // (Low down, from where it is out of sight: under it, in it,
                // behind it — mostly.)
                let low = (s.by + s.on).filter { spots[$0].height < 40 }
                let hidden = low.filter { spots[$0].open < 0.5 }
                pool = !hidden.isEmpty && chance(0.8) ? hidden : (low.isEmpty ? s.by + s.on : low)
            case .foliage, .bloom:
                pool = s.on.isEmpty ? s.by : s.on
            default:
                pool = s.by.isEmpty ? s.on : s.by
            }
        }
        pool = pool.filter { canWalk(kind, spots[$0]) }
        if pool.isEmpty {
            // In from nowhere in particular: a crack in the floor, some way off.
            pool = near(CGRect(x: p.x - 900, y: floor - 20, width: 1800, height: 60)).filter {
                spots[$0].facing == .up && spots[$0].owner == 0 && abs(spots[$0].point.x - p.x) > 200
            }
        }
        guard let i = pool.randomElement() else { return nil }
        let e = spots[i]
        let dir: CGFloat = chance(0.5) ? 1 : -1
        return EcoArrival(kind: kind, site: site, feature: s?.feature, at: e.point, anchor: e.anchor, dir: dir,
                          count: kind == .ant ? Int.random(in: 2...3) : 1, patch: patch, land: nil)
    }

    /// Whether a creature of `k` can walk on that spot (see `Prey.walkable`:
    /// an ant anything, a ladybug all but undersides, a beetle up a fair
    /// slope, the rest only what is near enough flat).
    func canWalk(_ k: PreyKind, _ e: EcoSpot) -> Bool { Prey.walkable(k, normal: e.normal) }

    /// The spot on `loop` (any, if nil) nearest `p`, within `within`.
    func spot(near p: V2, within r: CGFloat, loop: String? = nil) -> EcoSpot? {
        var best: (d: CGFloat, i: Int)?
        for i in near(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) {
            if let loop, spots[i].anchor.loopID != loop { continue }
            let d = spots[i].point.distance(to: p)
            if d < r, d < best?.d ?? .greatestFiniteMagnitude { best = (d, i) }
        }
        return best.map { spots[$0.i] }
    }

    // MARK: Where things go

    /// Somewhere for `k` to go for `use`, near `p`: weighed by how much it
    /// likes what the spot is on (and a little of anywhere, so nothing is
    /// certain), how near it is and — for a walker — only on `loop`, the
    /// surface it is on. `site`: only on or by that site.
    func haunt(_ use: Haunt, for k: PreyKind, near p: V2, within r: CGFloat, loop: String? = nil, site: Int? = nil,
               avoiding threat: V2? = nil) -> EcoSpot? {
        let box = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        var liking: [Int: CGFloat] = [:]
        var byRoom: [(CGRect, CGFloat)] = []
        for (i, s) in sites.enumerated() where site == nil || site == i {
            guard s.rect.insetBy(dx: -r, dy: -r).contains(p.point) else { continue }
            let w: CGFloat
            switch use {
            case .land, .rest: w = pull(s, k)
            case .hide: w = s.feature.hides ? s.strength : 0
            case .shelter: w = 0.3
            }
            guard w > 0 else { continue }
            if s.thing > 0 { liking[s.thing] = max(liking[s.thing] ?? 0, w) } else { byRoom.append((s.rect, w)) }
            if use == .hide || use == .shelter { byRoom.append((s.rect.insetBy(dx: -24, dy: -10), w)) }
        }
        var best: (score: CGFloat, i: Int)?
        for i in near(box) {
            let e = spots[i]
            if let loop, e.anchor.loopID != loop { continue }
            let d = e.point.distance(to: p)
            guard d < r else { continue }
            if let site, !sites[site].on.contains(i), !sites[site].by.contains(i) { continue }
            var like = liking[e.owner] ?? 0
            for (rr, w) in byRoom where rr.contains(e.point.point) { like = max(like, w * 0.8) }
            var score: CGFloat
            switch use {
            case .land:
                guard e.facing != .down || k == .moth || k == .mosquito else { continue }
                if k == .mosquito, e.facing == .up, like < 0.5 { continue }
                score = 0.08 + like
            case .rest:
                guard e.facing != .down || k == .moth else { continue }
                score = (0.1 + like) * (0.4 + clamp(e.height / 160, 0, 1.2)) * (e.open < 0.5 ? 1.2 : 1)
            case .hide:
                guard canWalk(k, e) else { continue }
                // Out of sight: under something (well under it), in by what hides it.
                score = (like + 0.05) * (e.deep ? 2.2 : e.open == 0 ? 1.4 : e.open < 0.5 ? 0.9 : 0.35) * (e.height < 60 ? 1 : 0.4)
            case .shelter:
                guard e.open < 0.34 else { continue }
                if loop != nil, !canWalk(k, e) { continue }
                // (Well in under it, not on the very edge of the dry.)
                score = (0.5 + like) * (e.deep ? 2 : e.open == 0 ? 0.9 : 0.35)
            }
            if let threat, e.point.distance(to: threat) < 90 { score *= 0.2 }
            score *= randRange(0.7, 1.3) / (1 + d / (use == .shelter ? 90 : 160))
            if score > best?.score ?? 0 { best = (score, i) }
        }
        return best.map { spots[$0.i] }
    }

    /// A light near `p`, after dark (for a moth to go round).
    func light(near p: V2, within r: CGFloat) -> V2? {
        guard night else { return nil }
        var best: (d: CGFloat, c: V2)?
        for s in sites where s.feature == .glow {
            let it = items[s.thing]
            // (The light itself: low on something hanging, high on a lamp.)
            let c = V2(s.rect.midX, s.rect.minY + s.rect.height * (it?.kind.hangs == true ? 0.25 : 0.8))
            let d = c.distance(to: p)
            if d < r, d < best?.d ?? .greatestFiniteMagnitude { best = (d, c) }
        }
        return best?.c
    }

    /// Open water near `p`, and a point in the air over it.
    func water(near p: V2, within r: CGFloat) -> (surface: CGRect, over: V2)? {
        var best: (d: CGFloat, w: CGRect)?
        for s in sites where s.feature == .water {
            guard let w = items[s.thing]?.water else { continue }
            let d = V2(w.midX, w.midY).distance(to: p)
            if d < r, d < best?.d ?? .greatestFiniteMagnitude { best = (d, w) }
        }
        guard let w = best?.w else { return nil }
        return (w, V2(w.midX + randRange(-0.35, 0.35) * w.width, w.maxY + randRange(22, 70)))
    }

    /// How hidden something keeping still at `p` is: under bark, in the
    /// litter, in the dark — 0 out in plain view.
    func concealment(at p: V2) -> CGFloat {
        var best: CGFloat = 0
        for s in sites where s.feature.hides && s.rect.insetBy(dx: -16, dy: -14).contains(p.point) {
            let covered = sky.roof(over: p + V2(0, 2), reach: 90) != nil
            let c: CGFloat = s.feature == .litter ? 0.65 : covered ? 0.85 : 0.35
            best = max(best, c * min(1, 0.5 + s.strength))
        }
        return best
    }

    /// Open to the sky at `p` (see `SkyCover.open`) — over and above thing
    /// `ignoring`, if given.
    func open(at p: V2, ignoring: Int? = nil) -> CGFloat { sky.open(at: p, ignoring: ignoring) }

    /// How much prey comes about `p` just now, 0…1: what draws it there, by
    /// the hour (flies to flowers by day, moths to a light at night), and
    /// what is loose there already.
    func preyPull(at p: V2, loose: [V2] = []) -> CGFloat {
        var v: CGFloat = 0
        for s in sites {
            let gap = V2(max(s.rect.minX - p.x, 0, p.x - s.rect.maxX), max(s.rect.minY - p.y, 0, p.y - s.rect.maxY)).length
            guard gap < 240 else { continue }
            let k = PreyKind.allCases.reduce(CGFloat(0)) { $0 + pull(s, $1) * (($1 == .ladybug) ? 0.2 : 1) }
            v += k * (1 - gap / 240) * 0.18
        }
        v += CGFloat(loose.filter { $0.distance(to: p) < 260 }.count) * 0.3
        return clamp(v, 0, 1)
    }

    /// Where a creature might be lying low near `p`: a spot by bark, in the
    /// litter or at the way into somewhere dark, to stand at and probe from
    /// — best first.
    func hidingPlaces(near p: V2, within r: CGFloat) -> [(site: Int, stand: EcoSpot, probe: V2)] {
        var out: [(site: Int, stand: EcoSpot, probe: V2, score: CGFloat)] = []
        for (i, s) in sites.enumerated() where s.feature.hides {
            let c = V2(s.rect.midX, s.rect.minY)
            let d = c.distance(to: p)
            guard d < r else { continue }
            // (Stood on the floor by it, looking in under it.)
            let standing = s.by.filter { spots[$0].facing == .up && spots[$0].height < 50 }
            guard let st = standing.min(by: { spots[$0].point.distance(to: p) < spots[$1].point.distance(to: p) }) else { continue }
            let hidden = s.by.filter { spots[$0].open < 0.5 && spots[$0].height < 50 }.map { spots[$0].surface }
            let probe = hidden.min(by: { $0.distance(to: spots[st].point) < $1.distance(to: spots[st].point) })
                ?? V2(clamp(spots[st].point.x, s.rect.minX, s.rect.maxX), s.rect.minY + 4)
            out.append((i, spots[st], probe, s.strength / (1 + d / 500)))
        }
        return out.sorted { $0.score > $1.score }.map { ($0.site, $0.stand, $0.probe) }
    }

    /// Tools only: a word on how it is.
    var debugSummary: String {
        let counts = Dictionary(grouping: sites, by: \.feature).map { "\($0.key.rawValue) \($0.value.count)" }.sorted().joined(separator: ", ")
        return String(format: "%d sites (%@), %d spots, %d drops, %d wet spots, %d remains, rain %.2f since %.0fs",
                      sites.count, counts, spots.count, droplets.count, wetSpots.count, remains.count, Double(weather.rain), Double(min(sinceRain, 99_999)))
    }
    var debugWetSpots: Int { wetSpots.count }
    /// Tools only: drops beaded everywhere they could be, at once.
    func debugBead(_ n: Int, r: CGFloat = 1.8) {
        for s in wetSpots.shuffled().prefix(n) {
            droplets.append(Droplet(id: nextID, thing: s.thing, p: s.p, r: r, reachable: s.reachable))
            nextID += 1
            bump(s.thing)
        }
    }
    /// Tools only: rain as long ago as this.
    func debugSinceRain(_ s: CGFloat) { sinceRain = s }
    func debugWarm(_ id: Int, _ v: CGFloat) { warmth[id] = v }
}
