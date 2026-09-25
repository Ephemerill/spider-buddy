import AppKit

// MARK: - Model

/// The scenery behind the glass.
enum Biome: String, Codable, CaseIterable {
    case forest, jungle, desert, meadow, cave, beach, tundra, night

    var label: String {
        switch self {
        case .forest: return "Forest"
        case .jungle: return "Jungle"
        case .desert: return "Desert"
        case .meadow: return "Meadow"
        case .cave: return "Cave"
        case .beach: return "Beach"
        case .tundra: return "Snowfall"
        case .night: return "Moonlit"
        }
    }

    /// A few words on what moves in it, for the picker.
    var blurb: String {
        switch self {
        case .forest: return "Pines, sunbeams and falling leaves"
        case .jungle: return "Mist, vines and butterflies"
        case .desert: return "Dunes, heat and drifting sand"
        case .meadow: return "Clouds, long grass and pollen"
        case .cave: return "Glowing crystals and drips"
        case .beach: return "Waves, gulls and sea sparkle"
        case .tundra: return "Snow under the northern lights"
        case .night: return "Stars, moonlight and fireflies"
        }
    }
}

/// Things to put in the habitat. Some are furniture it can climb on; some
/// are just scenery.
enum HabitatItemKind: String, Codable, CaseIterable {
    // Perches, in the order the picker shows them.
    case log, branch, driftwood, corkBark, hide, rock, boulder, bamboo, cactus, plant, vine, waterDish
    // Plants and details.
    case fern, grass, flower, succulent, mushrooms, moss, leafPile, pebbles, twigs, crystal

    var label: String {
        switch self {
        case .log: return "Log"
        case .branch: return "Branch"
        case .driftwood: return "Driftwood"
        case .corkBark: return "Cork Bark"
        case .hide: return "Hollow Log"
        case .rock: return "Rock"
        case .boulder: return "Boulder"
        case .bamboo: return "Bamboo"
        case .cactus: return "Cactus"
        case .plant: return "Leafy Plant"
        case .vine: return "Hanging Vine"
        case .waterDish: return "Water Dish"
        case .fern: return "Fern"
        case .grass: return "Tall Grass"
        case .flower: return "Flowers"
        case .succulent: return "Succulent"
        case .mushrooms: return "Mushrooms"
        case .moss: return "Moss"
        case .leafPile: return "Leaf Litter"
        case .pebbles: return "Pebbles"
        case .twigs: return "Twigs"
        case .crystal: return "Crystals"
        }
    }

    /// Climbable, or just to look at.
    var climbable: Bool {
        switch self {
        case .log, .branch, .driftwood, .corkBark, .hide, .rock, .boulder, .bamboo, .cactus, .plant, .vine, .waterDish: return true
        default: return false
        }
    }

    /// Size in scene points (the scene is `HabitatLayout.width` across).
    var defaultSize: CGSize {
        switch self {
        case .log: return CGSize(width: 180, height: 50)
        case .branch: return CGSize(width: 230, height: 130)
        case .driftwood: return CGSize(width: 200, height: 56)
        case .corkBark: return CGSize(width: 74, height: 210)
        case .hide: return CGSize(width: 130, height: 66)
        case .rock: return CGSize(width: 76, height: 44)
        case .boulder: return CGSize(width: 140, height: 92)
        case .bamboo: return CGSize(width: 60, height: 250)
        case .cactus: return CGSize(width: 70, height: 150)
        case .plant: return CGSize(width: 120, height: 150)
        case .vine: return CGSize(width: 40, height: 230)
        case .waterDish: return CGSize(width: 96, height: 26)
        case .fern: return CGSize(width: 130, height: 90)
        case .grass: return CGSize(width: 90, height: 84)
        case .flower: return CGSize(width: 80, height: 80)
        case .succulent: return CGSize(width: 64, height: 46)
        case .mushrooms: return CGSize(width: 66, height: 46)
        case .moss: return CGSize(width: 120, height: 24)
        case .leafPile: return CGSize(width: 130, height: 26)
        case .pebbles: return CGSize(width: 90, height: 20)
        case .twigs: return CGSize(width: 96, height: 30)
        case .crystal: return CGSize(width: 64, height: 70)
        }
    }

    /// Hangs from the lid rather than standing on the ground.
    var hangs: Bool { self == .vine }

    /// Moves on its own — sways in the air of the tank, glows or ripples.
    var sways: Bool {
        switch self {
        case .vine, .plant, .fern, .grass, .flower, .bamboo: return true
        default: return false
        }
    }

    /// Where it goes by default: low things and foliage can go in front of
    /// the spider; furniture it climbs is always behind it.
    var canGoInFront: Bool { !climbable }
}

struct HabitatItem: Codable, Equatable, Identifiable {
    var id: Int
    var kind: HabitatItemKind
    /// Centre across. Standing things: `y` is how far above the ground its
    /// base is (0 on the ground). Hanging things: `y` is its top (the lid
    /// is `HabitatLayout.height`).
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var flipped = false
    var seed = 0
    /// Drawn in front of the spider (foreground foliage), or behind it.
    var front = false

    /// Its rectangle in scene points.
    var rect: CGRect {
        kind.hangs ? CGRect(x: x - w / 2, y: y - h, width: w, height: h)
                   : CGRect(x: x - w / 2, y: HabitatLayout.ground + y, width: w, height: h)
    }

    var onGround: Bool { !kind.hangs && y < 2 }
    var inFront: Bool { front && kind.canGoInFront }
}

/// The shape of the tank's scene, in scene points: a fixed aspect, with
/// the substrate along the bottom and the air above it.
enum HabitatLayout {
    static let width: CGFloat = 900
    static let height: CGFloat = 540
    /// The top of the substrate: what it walks on.
    static let ground: CGFloat = 74
    static var aspect: CGFloat { height / width }
}

struct Habitat: Codable, Equatable {
    var biome: Biome = .forest
    var items: [HabitatItem] = []
    var nextID = 1

    static let key = "habitat"

    static func load() -> Habitat {
        guard let data = UserDefaults.standard.data(forKey: key),
              var h = try? JSONDecoder().decode(Habitat.self, from: data) else { return .preset(.forestFloor) }
        h.clampAll()
        return h
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Habitat.key) }
    }

    @discardableResult
    mutating func add(_ kind: HabitatItemKind, at p: CGPoint, scale: CGFloat = 1) -> HabitatItem {
        let size = kind.defaultSize
        var item = HabitatItem(id: nextID, kind: kind, x: p.x, y: p.y, w: size.width * scale, h: size.height * scale,
                               flipped: Bool.random(), seed: Int.random(in: 1...9999), front: false)
        Habitat.clamp(&item)
        nextID += 1
        items.append(item)
        return item
    }

    /// Keeps a thing inside the tank: on or above the ground, under the lid.
    static func clamp(_ it: inout HabitatItem) {
        let W = HabitatLayout.width, H = HabitatLayout.height, G = HabitatLayout.ground
        it.w = min(max(it.w, 12), W * 0.8)
        it.h = min(max(it.h, 10), (H - G) * 0.96)
        it.x = min(max(it.x, it.w * 0.2), W - it.w * 0.2)
        if it.kind.hangs {
            it.y = min(max(it.y, G + it.h + 10), H)
        } else {
            it.y = min(max(it.y, 0), H - G - it.h)
        }
    }

    mutating func clampAll() {
        for i in items.indices { Habitat.clamp(&items[i]) }
    }

    // MARK: Presets

    enum Preset: String, CaseIterable {
        case forestFloor, jungleCanopy, desertScrub, meadow, cave, beach, tundra, moonlit, empty
        var label: String {
            switch self {
            case .forestFloor: return "Forest Floor"
            case .jungleCanopy: return "Jungle Canopy"
            case .desertScrub: return "Desert Scrub"
            case .meadow: return "Wildflower Meadow"
            case .cave: return "Crystal Cave"
            case .beach: return "Beachcomber"
            case .tundra: return "Winter Hollow"
            case .moonlit: return "Moonlit Glade"
            case .empty: return "Bare Tank"
            }
        }
        var biome: Biome {
            switch self {
            case .forestFloor, .empty: return .forest
            case .jungleCanopy: return .jungle
            case .desertScrub: return .desert
            case .meadow: return .meadow
            case .cave: return .cave
            case .beach: return .beach
            case .tundra: return .tundra
            case .moonlit: return .night
            }
        }
    }

    /// Laid out on the 900 × 540 scene. For a standing thing the second
    /// number is its height off the ground; for a hanging one, its top.
    static func preset(_ p: Preset) -> Habitat {
        var h = Habitat()
        h.biome = p.biome
        var seed = 11
        func put(_ kind: HabitatItemKind, _ x: CGFloat, _ y: CGFloat = 0, front: Bool = false, scale: CGFloat = 1, flipped: Bool = false) {
            var it = h.add(kind, at: CGPoint(x: x, y: kind.hangs && y == 0 ? HabitatLayout.height : y), scale: scale)
            it.flipped = flipped
            it.front = front
            seed = (seed * 7919 + 13) % 9973
            it.seed = seed + 1
            Habitat.clamp(&it)
            h.items[h.items.count - 1] = it
        }
        switch p {
        case .forestFloor:
            put(.corkBark, 92, scale: 1.1)
            put(.branch, 560, 26, scale: 1.1)
            put(.log, 330, scale: 1.15)
            put(.rock, 470)
            put(.plant, 770)
            put(.mushrooms, 395, 44, scale: 0.8)
            put(.moss, 210)
            put(.leafPile, 650)
            put(.vine, 690)
            put(.fern, 190, front: true)
            put(.grass, 860, front: true, scale: 0.9)
        case .jungleCanopy:
            put(.bamboo, 70, scale: 1.1)
            put(.branch, 280, 110, scale: 1.25)
            put(.branch, 640, 190, scale: 1.1, flipped: true)
            put(.vine, 170, scale: 1.2)
            put(.vine, 800)
            put(.plant, 790, scale: 1.2)
            put(.hide, 460, scale: 0.95)
            put(.waterDish, 610)
            put(.moss, 330)
            put(.flower, 700)
            put(.fern, 250, front: true, scale: 1.1)
            put(.fern, 560, front: true, scale: 0.85, flipped: true)
        case .desertScrub:
            put(.boulder, 200, scale: 1.1)
            put(.rock, 335)
            put(.cactus, 590, scale: 1.1)
            put(.cactus, 660, scale: 0.7, flipped: true)
            put(.driftwood, 440, scale: 0.9)
            put(.succulent, 520)
            put(.pebbles, 760)
            put(.waterDish, 820, scale: 0.9)
            put(.succulent, 120, front: true, scale: 0.9)
        case .meadow:
            put(.log, 220)
            put(.rock, 350, scale: 0.8)
            put(.branch, 780, 20, scale: 0.9, flipped: true)
            put(.plant, 560, scale: 0.9)
            put(.flower, 430, scale: 1.1)
            put(.flower, 660, scale: 0.8)
            put(.moss, 610)
            put(.grass, 110, front: true)
            put(.flower, 300, front: true, scale: 0.8)
            put(.grass, 740, front: true, scale: 1.1)
        case .cave:
            put(.boulder, 170, scale: 1.2)
            put(.boulder, 730)
            put(.rock, 430)
            put(.corkBark, 560, scale: 0.9)
            put(.crystal, 300, scale: 1.1)
            put(.crystal, 830, scale: 0.8)
            put(.mushrooms, 490, scale: 1.1)
            put(.pebbles, 640)
            put(.vine, 380, scale: 0.8)
            put(.crystal, 90, front: true, scale: 0.7)
        case .beach:
            put(.driftwood, 280, scale: 1.3)
            put(.rock, 520)
            put(.rock, 575, scale: 0.6)
            put(.boulder, 820, scale: 0.8)
            put(.pebbles, 660)
            put(.twigs, 420)
            put(.waterDish, 720, scale: 1.1)
            put(.grass, 110, scale: 1.1)
            put(.succulent, 610, front: true, scale: 0.8)
        case .tundra:
            put(.boulder, 300)
            put(.rock, 160)
            put(.log, 620, scale: 1.1)
            put(.branch, 820, 50, scale: 0.8, flipped: true)
            put(.twigs, 460)
            put(.moss, 760)
            put(.pebbles, 380)
            put(.grass, 70, front: true, scale: 0.8)
        case .moonlit:
            put(.log, 340, scale: 1.1)
            put(.branch, 640, 70)
            put(.plant, 810)
            put(.rock, 490)
            put(.vine, 150)
            put(.mushrooms, 210)
            put(.crystal, 570, scale: 0.6)
            put(.fern, 260, front: true)
            put(.grass, 700, front: true, scale: 0.8)
        case .empty:
            break
        }
        return h
    }

    /// A fresh take on a layout: the same pieces, shuffled about a little
    /// and resized, so no two are the same.
    static func surprise() -> Habitat {
        let presets = Preset.allCases.filter { $0 != .empty }
        var h = Habitat.preset(presets.randomElement()!)
        if Bool.random() { h.biome = Biome.allCases.randomElement()! }
        for i in h.items.indices {
            h.items[i].x += CGFloat.random(in: -70...70)
            h.items[i].seed = Int.random(in: 1...9999)
            let k = CGFloat.random(in: 0.85...1.2)
            h.items[i].w *= k; h.items[i].h *= k
            if Bool.random() { h.items[i].flipped.toggle() }
            Habitat.clamp(&h.items[i])
        }
        return h
    }
}

// MARK: - Surfaces

extension Habitat {
    /// The part of a thing it can stand on as a block, in scene points —
    /// inside the drawing, so its feet go on the wood or the stone and not
    /// on the air around a rounded top.
    static func solidRect(_ it: HabitatItem) -> CGRect? {
        let r = it.rect
        func inset(_ l: CGFloat, _ rgt: CGFloat, top: CGFloat) -> CGRect {
            let a = it.flipped ? rgt : l, b = it.flipped ? l : rgt
            return CGRect(x: r.minX + r.width * a, y: r.minY, width: r.width * (1 - a - b), height: r.height * top)
        }
        switch it.kind {
        case .log: return inset(0.04, 0.04, top: 0.92)
        case .hide: return inset(0.04, 0.04, top: 0.9)
        case .driftwood: return inset(0.08, 0.1, top: 0.62)
        case .rock: return inset(0.14, 0.14, top: 0.86)
        case .boulder: return inset(0.12, 0.12, top: 0.9)
        case .corkBark: return inset(0.1, 0.1, top: 0.98)
        case .cactus: return inset(0.3, 0.3, top: 0.97)
        case .bamboo: return inset(0.32, 0.32, top: 0.94)
        case .waterDish: return inset(0.02, 0.02, top: 0.72)
        case .plant: return CGRect(x: r.midX - r.width * 0.18, y: r.minY, width: r.width * 0.36, height: r.height * 0.2)   // the pot
        case .vine: return CGRect(x: r.midX - max(r.width * 0.18, 4), y: r.minY + 8, width: max(r.width * 0.36, 8), height: r.height - 8)
        default: return nil
        }
    }

    /// Everything it can walk on, in screen coordinates, for a scene at
    /// `scene` (the whole glass, substrate included): one closed loop
    /// round the inside of the tank — along the ground and up and over
    /// whatever stands on it, up the glass, across under the lid and back
    /// down — and a loop of its own for anything off the ground (a branch,
    /// a vine, the leafy top of a plant).
    func surfaces(in scene: CGRect, standoff off: CGFloat) -> (air: CGRect, loops: [SurfaceLoop]) {
        let sx = scene.width / HabitatLayout.width, sy = scene.height / HabitatLayout.height
        func toScreen(_ r: CGRect) -> CGRect {
            CGRect(x: scene.minX + r.minX * sx, y: scene.minY + r.minY * sy, width: r.width * sx, height: r.height * sy)
        }
        func pt(_ p: V2) -> V2 { V2(scene.minX + p.x * sx, scene.minY + p.y * sy) }
        let groundY = scene.minY + HabitatLayout.ground * sy
        let air = CGRect(x: scene.minX, y: groundY, width: scene.width, height: scene.maxY - groundY)
        let inner = air.insetBy(dx: off, dy: off)
        guard inner.width > 40, inner.height > 40 else { return (air, []) }

        // The skyline of what stands on the ground, stood off by the body.
        var blocks: [CGRect] = []
        var loose: [SurfaceLoop] = []
        for (i, it) in items.enumerated() where it.kind.climbable {
            let id = "item:\(it.id)"
            let depth = items.count - i
            if it.kind == .branch {
                let pts = Habitat.branchPoints(it.rect, flipped: it.flipped).map(pt)
                loose += SurfaceMap.stripLoops(id: id, points: pts, standoff: off, depth: depth, rect: toScreen(it.rect))
                continue
            }
            if it.kind == .plant {
                // The pot stands on the ground; the broad leaves up top are a perch.
                let r = it.rect
                let pad = CGRect(x: r.minX + r.width * 0.2, y: r.maxY - r.height * 0.24, width: r.width * 0.6, height: r.height * 0.16)
                loose.append(SurfaceMap.boxLoop(id: id + ":top", rect: toScreen(pad), standoff: off, depth: depth))
            }
            guard let solid = Habitat.solidRect(it) else { continue }
            let s = toScreen(solid)
            if it.onGround {
                blocks.append(s)
            } else {
                loose.append(SurfaceMap.boxLoop(id: id, rect: s, standoff: off, depth: depth))
            }
        }

        let floor = Habitat.skyline(blocks, from: inner.minX, to: inner.maxX, base: groundY, standoff: off, ceiling: inner.maxY - 24)
        let hl = floor.heights.first ?? inner.minY, hr = floor.heights.last ?? inner.minY
        let bl = V2(inner.minX, hl), br = V2(inner.maxX, hr)
        let tr = V2(inner.maxX, inner.maxY), tl = V2(inner.minX, inner.maxY)
        var rim = SurfaceLoop(id: "screen:0", kind: .screenBorder,
                              segs: floor.segs + [Seg(br, tr, .left), Seg(tr, tl, .down), Seg(tl, bl, .right)],
                              closed: true, depth: 1_000_000, rect: inner)
        rim.edge = floor.edge + Array(SurfaceMap.rectEdge(air, inside: true).dropFirst())
        return (air, [rim] + loose)
    }

    /// The ground as it walks it, left to right: flat where there is
    /// nothing, and up the near side, over the top and down the far side
    /// of anything standing on it — as the desktop's floor does the Dock.
    /// `heights` are the body's height at the two ends, for the walls.
    static func skyline(_ blocks: [CGRect], from x0: CGFloat, to x1: CGFloat, base: CGFloat, standoff off: CGFloat,
                        ceiling: CGFloat) -> (segs: [Seg], edge: [Seg], heights: [CGFloat]) {
        // The body's line: each block grown by the body's height.
        func profile(_ rects: [CGRect], lift: CGFloat, grow: CGFloat) -> [(x0: CGFloat, x1: CGFloat, y: CGFloat)] {
            let grown = rects.map { CGRect(x: $0.minX - grow, y: $0.minY, width: $0.width + grow * 2, height: $0.height + lift) }
            var xs = Set<CGFloat>([x0, x1])
            for g in grown {
                if g.minX > x0 && g.minX < x1 { xs.insert(g.minX) }
                if g.maxX > x0 && g.maxX < x1 { xs.insert(g.maxX) }
            }
            let sorted = xs.sorted()
            var runs: [(x0: CGFloat, x1: CGFloat, y: CGFloat)] = []
            for i in 0..<(sorted.count - 1) {
                let a = sorted[i], b = sorted[i + 1]
                guard b - a > 0.01 else { continue }
                let m = (a + b) / 2
                var y = base + lift
                for g in grown where g.minX < m && g.maxX > m { y = max(y, g.maxY) }
                y = min(y, ceiling)
                if let last = runs.last, abs(last.y - y) < 0.5 {
                    runs[runs.count - 1].x1 = b
                } else {
                    runs.append((a, b, y))
                }
            }
            // A gap narrower than the spider between two blocks is filled
            // in: it steps across, not down into a crack.
            var i = 1
            while i < runs.count - 1 {
                let r = runs[i]
                if r.x1 - r.x0 < max(off * 1.2, 10), r.y < runs[i - 1].y, r.y < runs[i + 1].y {
                    runs[i].y = min(runs[i - 1].y, runs[i + 1].y)
                    // Merge with whichever neighbour now matches.
                    if abs(runs[i].y - runs[i - 1].y) < 0.5 { runs[i - 1].x1 = runs[i].x1; runs.remove(at: i); continue }
                    if abs(runs[i].y - runs[i + 1].y) < 0.5 { runs[i + 1].x0 = runs[i].x0; runs.remove(at: i); continue }
                }
                i += 1
            }
            return runs
        }
        func segs(_ runs: [(x0: CGFloat, x1: CGFloat, y: CGFloat)]) -> [Seg] {
            var out: [Seg] = []
            for (i, r) in runs.enumerated() {
                if i > 0 {
                    let prev = runs[i - 1]
                    if r.y > prev.y + 0.5 {
                        out.append(Seg(V2(r.x0, prev.y), V2(r.x0, r.y), .left))
                    } else if r.y < prev.y - 0.5 {
                        out.append(Seg(V2(r.x0, prev.y), V2(r.x0, r.y), .right))
                    }
                }
                out.append(Seg(V2(r.x0, r.y), V2(r.x1, r.y), .up))
            }
            return out
        }
        let body = profile(blocks, lift: off, grow: off)
        let feet = profile(blocks, lift: 0, grow: 0)
        return (segs(body), segs(feet), [body.first?.y ?? base + off, body.last?.y ?? base + off])
    }

    /// The line of a branch: from its low end up to its tip, with a bend.
    static func branchPoints(_ r: CGRect, flipped: Bool) -> [V2] {
        let a = V2(r.minX + r.width * 0.04, r.minY + r.height * 0.1)
        let m = V2(r.minX + r.width * 0.48, r.minY + r.height * 0.52)
        let b = V2(r.maxX - r.width * 0.05, r.minY + r.height * 0.86)
        let pts = [a, m, b]
        return flipped ? pts.map { V2(r.maxX + r.minX - $0.x, $0.y) }.reversed() : pts
    }
}
