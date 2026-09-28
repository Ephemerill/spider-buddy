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

    /// Size in world points (the same as the screen's).
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
    /// Centre across, in world points. Standing things: `y` is how far above
    /// the ground its base is (0 on the ground). Hanging things: `y` is its
    /// top (the lid is the top of the world).
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var flipped = false
    var seed = 0
    /// Drawn in front of the spider (foreground foliage), or behind it.
    var front = false

    /// Its rectangle in the world.
    var rect: CGRect {
        kind.hangs ? CGRect(x: x - w / 2, y: y - h, width: w, height: h)
                   : CGRect(x: x - w / 2, y: HabitatLayout.ground + y, width: w, height: h)
    }

    var onGround: Bool { !kind.hangs && y < 2 }
    var inFront: Bool { front && kind.canGoInFront }
}

/// The habitat's measurements. Its world is in points one to one with the
/// screen's: the spider, what it hunts and the furniture are the same size
/// in there as they are on the desktop, and the window is a pane of glass
/// onto part of it (see HabitatCamera.swift).
enum HabitatLayout {
    /// The tank as it was when all of it had to fit in its window: a
    /// 900 × 540 scene. The scenery is still drawn to its proportions, the
    /// picker's pictures are laid out on it, and a habitat saved back then
    /// is moved into a world from it.
    static let width: CGFloat = 900
    static let height: CGFloat = 540
    static var aspect: CGFloat { height / width }
    /// The top of the substrate: what it walks on.
    static let ground: CGFloat = 74

    /// The world for a display this size: about two and three-quarter
    /// screens across and a screen and a third high — a good deal more
    /// than the window shows, but still one tank.
    static func world(for screen: CGSize) -> CGSize {
        CGSize(width: clamp((screen.width * 2.75).rounded(), 3000, 5600),
               height: clamp((screen.height * 1.35).rounded(), 1050, 1600))
    }

    /// The world a new habitat gets, from the main display. (Kept with the
    /// habitat after that: moving to another display changes how much of
    /// it the window shows, not where anything in it is.)
    static var defaultWorld: CGSize {
        world(for: NSScreen.main?.visibleFrame.size ?? CGSize(width: 1470, height: 920))
    }
}

struct Habitat: Codable, Equatable {
    var biome: Biome = .forest
    var items: [HabitatItem] = []
    var nextID = 1
    /// How big its world is. Missing from a habitat saved before the tank
    /// was bigger than its window — `load` moves one of those into a world.
    var world: CGSize?

    init() {}
    init(biome: Biome, world: CGSize) {
        self.biome = biome
        self.world = world
    }

    /// The world's size: the old scene's for a habitat not yet moved into one.
    var size: CGSize { world ?? CGSize(width: HabitatLayout.width, height: HabitatLayout.height) }
    var bounds: CGRect { CGRect(origin: .zero, size: size) }

    static let key = "habitat"

    static func load() -> Habitat {
        guard let data = UserDefaults.standard.data(forKey: key),
              var h = try? JSONDecoder().decode(Habitat.self, from: data) else { return .preset(.forestFloor) }
        if h.world == nil {
            h = h.movedIntoWorld(HabitatLayout.defaultWorld)
            h.save()
        }
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
        Habitat.clamp(&item, in: self.size)
        nextID += 1
        items.append(item)
        return item
    }

    /// Keeps a thing inside a world this size: on or above the ground,
    /// under the lid.
    static func clamp(_ it: inout HabitatItem, in world: CGSize) {
        let W = world.width, H = world.height, G = HabitatLayout.ground
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
        let s = size
        for i in items.indices { Habitat.clamp(&items[i], in: s) }
    }

    // MARK: From the old tank

    /// A habitat from before the tank was bigger than its window, moved into
    /// a world. A ready-made layout still just as it came becomes the new
    /// layout of that name (in whatever scenery it was given); one made its
    /// own is kept exactly as it was, stood in the middle of the world —
    /// where the window first opens — with hanging things still hanging
    /// from the lid, and as far down from it as they were.
    func movedIntoWorld(_ world: CGSize) -> Habitat {
        if world == size, self.world != nil { return self }
        for p in Preset.allCases where !items.isEmpty && Habitat.sameLayout(Habitat.legacyItems(p), items) {
            var h = Habitat.preset(p, world: world)
            h.biome = biome
            return h
        }
        var h = Habitat(biome: biome, world: world)
        h.items = items
        h.nextID = nextID
        let dx = ((world.width - size.width) / 2).rounded()
        let lift = world.height - size.height
        for i in h.items.indices {
            h.items[i].x += dx
            if h.items[i].kind.hangs { h.items[i].y += lift; h.items[i].h += lift }
        }
        h.clampAll()
        return h
    }

    /// Whether two lists of things are the same layout: the same things, in
    /// the same order, flipped and layered the same, each within a few
    /// points of the same place and size (a stray click that nudged
    /// something doesn't make a tank anyone's own).
    static func sameLayout(_ a: [HabitatItem], _ b: [HabitatItem]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { p, q in
            p.kind == q.kind && p.flipped == q.flipped && p.front == q.front
                && abs(p.x - q.x) < 6 && abs(p.y - q.y) < 6 && abs(p.w - q.w) < 6 && abs(p.h - q.h) < 6
        }
    }

    /// The ready-made layouts as they were on the old 900 × 540 scene: what
    /// a saved habitat is checked against, and the middle of each new one.
    static func legacyItems(_ p: Preset) -> [HabitatItem] {
        var h = Habitat()
        var seed = 11
        func put(_ kind: HabitatItemKind, _ x: CGFloat, _ y: CGFloat = 0, front: Bool = false, scale: CGFloat = 1, flipped: Bool = false) {
            var it = h.add(kind, at: CGPoint(x: x, y: kind.hangs && y == 0 ? HabitatLayout.height : y), scale: scale)
            it.flipped = flipped
            it.front = front
            seed = (seed * 7919 + 13) % 9973
            it.seed = seed + 1
            Habitat.clamp(&it, in: h.size)
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
        return h.items
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
        /// What lies either side of the old tank's arrangement, from the
        /// middle outward; the last of each is the part by the glass at that
        /// end, whatever room there is for the others.
        var sides: (left: [HabitatRegion.Kind], right: [HabitatRegion.Kind]) {
            switch self {
            case .forestFloor: return ([.shelter, .thicket, .canopy], [.clearing, .rocks, .canopy])
            case .jungleCanopy: return ([.pool, .thicket, .canopy], [.thicket, .clearing, .canopy])
            case .desertScrub: return ([.clearing, .pool, .canopy], [.thicket, .shelter, .rocks])
            case .meadow: return ([.clearing, .pool, .canopy], [.thicket, .shelter, .canopy])
            case .cave: return ([.pool, .rocks, .canopy], [.shelter, .thicket, .rocks])
            case .beach: return ([.pool, .clearing, .rocks], [.rocks, .thicket, .canopy])
            case .tundra: return ([.clearing, .rocks, .canopy], [.shelter, .thicket, .canopy])
            case .moonlit: return ([.clearing, .thicket, .canopy], [.pool, .shelter, .canopy])
            case .empty: return ([], [])
            }
        }
    }

    /// A ready-made tank across the whole world: the old tank's arrangement
    /// in the middle, where the window first opens, a branch or two in the
    /// air above it, and either side of it parts with a character of their
    /// own (see `HabitatRegion.Kind`), with things to climb up into the air
    /// of the tank as well as along the ground.
    static func preset(_ p: Preset, world: CGSize = HabitatLayout.defaultWorld) -> Habitat {
        var b = LayoutBuilder(world: world, biome: p.biome, seed: UInt64(p.rawValue.unicodeScalars.reduce(7) { $0 &* 31 &+ Int($1.value) }))
        guard p != .empty else { return b.h }
        let mid = HabitatLayout.width
        let x0 = ((world.width - mid) / 2).rounded()
        for it in legacyItems(p) { b.putOld(it, dx: x0) }
        b.overhead(x0 + mid * 0.5)
        let (left, right) = p.sides
        b.fill(from: x0, to: 0, kinds: left)
        b.fill(from: x0 + mid, to: world.width, kinds: right)
        return b.h
    }

    /// A fresh tank, laid out part by part across the whole world — a
    /// thicket here, a clearing there, rocks, a pool, a stand of branches
    /// — never twice the same.
    static func surprise(world: CGSize = HabitatLayout.defaultWorld, biome: Biome? = nil) -> Habitat {
        var b = LayoutBuilder(world: world, biome: biome ?? Biome.allCases.randomElement()!, seed: UInt64.random(in: 1...UInt64.max))
        let n = max(3, Int((world.width / 760).rounded()))
        var kinds: [HabitatRegion.Kind] = []
        let all: [HabitatRegion.Kind] = [.thicket, .clearing, .canopy, .shelter, .pool, .rocks]
        // At least somewhere to hunt and somewhere to climb.
        let must: [HabitatRegion.Kind] = [.clearing, .canopy]
        while kinds.count < n {
            var k = b.dice.pick(all)
            if let last = kinds.last, k == last { continue }
            if kinds.count == n - must.count, let missing = must.first(where: { !kinds.contains($0) }) { k = missing }
            kinds.append(k)
        }
        b.fill(from: 0, to: world.width, kinds: kinds, open: true)
        return b.h
    }

    /// The parts it has, as they stand: stretches of the world with a
    /// character of their own, found from what is in them. A place to hang
    /// what the spider comes to know about its tank — favourite spots,
    /// where it hunts, where it sleeps — on something that lasts longer
    /// than a point: a stretch of the world, and the furniture in it by id.
    var regions: [HabitatRegion] { HabitatRegion.find(in: self) }
}

// MARK: - Regions

/// A part of the habitat with a character of its own.
struct HabitatRegion: Equatable {
    enum Kind: String, CaseIterable {
        /// Dense planting: somewhere to hide and to lie in wait.
        case thicket
        /// Open ground with a little litter on it: somewhere to hunt.
        case clearing
        /// A trunk and branches up into the air of the tank.
        case canopy
        /// Bark, a hollow log: somewhere to shelter.
        case shelter
        /// Water.
        case pool
        /// Stone.
        case rocks
        /// Bare substrate.
        case open

        var label: String {
            switch self {
            case .thicket: return "Thicket"
            case .clearing: return "Clearing"
            case .canopy: return "Branches"
            case .shelter: return "Shelter"
            case .pool: return "Pool"
            case .rocks: return "Rocks"
            case .open: return "Open Ground"
            }
        }
    }
    /// "region:<n>", counting from the left.
    var id: String
    var kind: Kind
    /// Across the world, from the ground to the lid.
    var rect: CGRect
    /// What stands in it.
    var items: [Int]

    /// The world cut into parts where the furniture thins out (no part
    /// wider than about a window and a half), each named for what is in it.
    static func find(in h: Habitat) -> [HabitatRegion] {
        let W = h.size.width, H = h.size.height
        let sorted = h.items.sorted { $0.x < $1.x }
        var cuts: [CGFloat] = [0]
        var reach: CGFloat = 0
        // (What hangs from the lid, and small things, don't join parts up.)
        for (i, it) in sorted.enumerated() where !it.kind.hangs && it.w > 60 {
            let lo = it.x - it.w / 2
            if i > 0, lo - reach > 150 { cuts.append(((lo + reach) / 2).rounded()) }
            reach = max(reach, it.x + it.w / 2)
        }
        cuts.append(W)
        // Long stretches split evenly.
        var bands: [(CGFloat, CGFloat)] = []
        for (a, b) in zip(cuts, cuts.dropFirst()) where b - a > 1 {
            let n = max(1, Int(ceil((b - a) / 1300)))
            for k in 0..<n { bands.append((a + (b - a) * CGFloat(k) / CGFloat(n), a + (b - a) * CGFloat(k + 1) / CGFloat(n))) }
        }
        return bands.enumerated().map { i, band in
            let inside = h.items.filter { $0.x >= band.0 && $0.x < band.1 }
            return HabitatRegion(id: "region:\(i)", kind: character(of: inside),
                                 rect: CGRect(x: band.0, y: 0, width: band.1 - band.0, height: H), items: inside.map(\.id))
        }
    }

    private static func character(of items: [HabitatItem]) -> Kind {
        func count(_ ks: Set<HabitatItemKind>) -> Int { items.filter { ks.contains($0.kind) }.count }
        if count([.waterDish]) > 0 { return .pool }
        if items.contains(where: { ($0.kind == .branch && $0.y > 150) || (!$0.kind.hangs && $0.h > 350) }) { return .canopy }
        if count([.rock, .boulder]) >= 2 { return .rocks }
        if count([.hide, .corkBark, .log, .driftwood]) >= 2 { return .shelter }
        if count([.plant, .fern, .grass, .bamboo, .cactus, .flower, .succulent]) >= 3 { return .thicket }
        return items.isEmpty ? .open : .clearing
    }
}

// MARK: - Laying a tank out

/// A seeded die, so a ready-made layout comes out the same every time.
struct LayoutDice {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed | 1 }
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 1_000_000) / 1_000_000
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
    mutating func chance(_ p: CGFloat) -> Bool { next() < p }
    mutating func pick<T>(_ xs: [T]) -> T { xs[min(Int(next() * CGFloat(xs.count)), xs.count - 1)] }
}

/// Puts furniture in a world a part at a time. Heights up into the air are
/// given for a world 1250 high and scaled to this one, so a taller tank's
/// branches are further up.
private struct LayoutBuilder {
    var h: Habitat
    var dice: LayoutDice
    let biome: Biome
    let W: CGFloat, H: CGFloat
    /// This world's air over the reference's.
    let lift: CGFloat

    init(world: CGSize, biome: Biome, seed: UInt64) {
        h = Habitat(biome: biome, world: world)
        dice = LayoutDice(seed)
        self.biome = biome
        W = world.width
        H = world.height
        lift = (world.height - HabitatLayout.ground) / (1250 - HabitatLayout.ground)
    }

    /// A thing at `x`, `y` up off the ground (hanging: from the lid), at
    /// `scale` its usual size — or `tall` times as tall, to reach further.
    @discardableResult
    mutating func put(_ kind: HabitatItemKind, _ x: CGFloat, _ y: CGFloat = 0, front: Bool = false, scale: CGFloat = 1,
                      tall: CGFloat? = nil, flipped: Bool? = nil) -> HabitatItem {
        var it = h.add(kind, at: CGPoint(x: x, y: kind.hangs ? H : y), scale: scale)
        if let tall { it.h = kind.defaultSize.height * tall }
        it.flipped = flipped ?? dice.chance(0.5)
        it.front = front && kind.canGoInFront
        it.seed = 1 + Int(dice.next() * 9998)
        Habitat.clamp(&it, in: h.size)
        h.items[h.items.count - 1] = it
        return it
    }

    /// A vine from the lid down to `bottom` above the ground.
    mutating func vine(_ x: CGFloat, down bottom: CGFloat) {
        let len = max(H - HabitatLayout.ground - bottom, 160)
        put(.vine, x, tall: len / HabitatItemKind.vine.defaultSize.height)
    }

    /// One of the old tank's things, moved `dx` along; hanging ones hang
    /// from this world's lid, as far down toward the ground as they were.
    mutating func putOld(_ old: HabitatItem, dx: CGFloat) {
        var it = old
        it.id = h.nextID
        h.nextID += 1
        it.x += dx
        if it.kind.hangs {
            let bottom = old.y - old.h
            it.y = H
            it.h = H - bottom
        }
        Habitat.clamp(&it, in: h.size)
        h.items.append(it)
    }

    /// Something up in the air over the middle: a branch to get up to from
    /// the glass or a vine, the way up into the rest of the tank.
    mutating func overhead(_ x: CGFloat) {
        let high = 420 * lift
        put(.branch, x - 160, high, scale: 1.45, flipped: false)
        put(.branch, x + 230, high + 190 * lift, scale: 1.3, flipped: true)
        put(.branch, x - 60, high + 400 * lift, scale: 1.2, flipped: false)
        if biome != .desert { vine(x + 60, down: high + 60); vine(x - 250, down: high + 360 * lift) }
    }

    /// Fills the world from `a` toward `b` (either way) with parts of
    /// these kinds, in turn, each 600–900 across. `open`: nothing either
    /// side to lean on — the first part starts right at `a`.
    mutating func fill(from a: CGFloat, to b: CGFloat, kinds: [HabitatRegion.Kind], open: Bool = false) {
        let span = abs(b - a)
        guard span > 200, !kinds.isEmpty else { return }
        let n = open ? kinds.count : max(1, Int((span / 780).rounded()))
        // With room for fewer than there are, the one by the glass is kept.
        let laid = n >= kinds.count ? (0..<n).map { kinds[$0 % kinds.count] } : Array(kinds.prefix(n - 1)) + [kinds.last!]
        let dir: CGFloat = b > a ? 1 : -1
        for (k, kind) in laid.enumerated() {
            let lo = a + dir * span * CGFloat(k) / CGFloat(n), hi = a + dir * span * CGFloat(k + 1) / CGFloat(n)
            region(kind, from: min(lo, hi), to: max(lo, hi))
        }
    }

    // MARK: The parts

    private var dry: Bool { biome == .desert || biome == .beach }

    /// The part being laid out: where it starts, and how wide it is.
    private var partX: CGFloat = 0, partW: CGFloat = 0

    /// A fraction of the way across the part, give or take a little.
    private mutating func at(_ f: CGFloat) -> CGFloat { partX + partW * f + dice.range(-1, 1) * partW * 0.03 }

    mutating func region(_ kind: HabitatRegion.Kind, from x0: CGFloat, to x1: CGFloat) {
        partX = x0
        partW = x1 - x0
        switch kind {
        case .thicket: thicket()
        case .clearing: clearing()
        case .canopy: canopy()
        case .shelter: shelter()
        case .pool: pool()
        case .rocks: rocks()
        case .open: if dice.chance(0.5) { put(.pebbles, at(0.5)) }
        }
    }

    private mutating func thicket() {
        switch biome {
        case .desert:
            put(.cactus, at(0.22), scale: dice.range(1.2, 1.6))
            put(.cactus, at(0.4), scale: dice.range(0.7, 0.9))
            put(.cactus, at(0.72), scale: dice.range(1.5, 2))
            put(.succulent, at(0.55))
            put(.succulent, at(0.86), scale: 0.8)
            put(.pebbles, at(0.3))
            put(.succulent, at(0.1), front: true, scale: 0.9)
        case .beach:
            put(.grass, at(0.18), scale: 1.3)
            put(.grass, at(0.34), scale: 1.1)
            put(.driftwood, at(0.55), scale: 0.9)
            put(.grass, at(0.74), scale: 1.4)
            put(.succulent, at(0.86))
            put(.twigs, at(0.45))
            put(.grass, at(0.62), front: true, scale: 1.1)
        case .cave:
            put(.mushrooms, at(0.18), scale: 1.3)
            put(.crystal, at(0.34), scale: 1.4)
            put(.corkBark, at(0.52), scale: 1.3, tall: 2.1)
            put(.mushrooms, at(0.66), scale: 1)
            put(.crystal, at(0.82), scale: 1.1)
            put(.moss, at(0.4))
            vine(at(0.6), down: 360 * lift)
            put(.crystal, at(0.1), front: true, scale: 0.8)
        case .tundra:
            put(.corkBark, at(0.3), scale: 1.3, tall: 2.4)
            put(.grass, at(0.15), scale: 0.8)
            put(.grass, at(0.5), scale: 0.9)
            put(.boulder, at(0.72), scale: 0.8)
            put(.twigs, at(0.86))
            put(.grass, at(0.62), front: true, scale: 0.8)
        default:
            put(.plant, at(0.18), scale: dice.range(1.1, 1.4))
            put(biome == .jungle ? .bamboo : .corkBark, at(0.38), scale: biome == .jungle ? 1.1 : 1.35, tall: dice.range(2.2, 2.8))
            put(.plant, at(0.6), scale: dice.range(1.2, 1.6))
            put(.fern, at(0.8), scale: 1.2)
            put(biome == .meadow ? .flower : .fern, at(0.3), scale: 1.1)
            put(biome == .meadow ? .flower : .moss, at(0.92))
            vine(at(0.5), down: 300 * lift)
            put(.fern, at(0.08), front: true, scale: 1.2)
            put(.grass, at(0.7), front: true, scale: 1.1)
        }
    }

    private mutating func clearing() {
        switch biome {
        case .desert, .beach:
            put(.pebbles, at(0.2))
            put(.twigs, at(0.45))
            put(.rock, at(0.66), scale: 0.7)
            put(.succulent, at(0.85), scale: 0.7)
        case .cave:
            put(.pebbles, at(0.25))
            put(.crystal, at(0.6), scale: 0.6)
            put(.pebbles, at(0.8), scale: 0.8)
        case .tundra:
            put(.twigs, at(0.3))
            put(.pebbles, at(0.62))
            put(.rock, at(0.8), scale: 0.6)
        default:
            put(.leafPile, at(0.2))
            put(biome == .meadow ? .flower : .twigs, at(0.42))
            put(.moss, at(0.62))
            put(.rock, at(0.8), scale: 0.7)
            put(biome == .meadow ? .grass : .mushrooms, at(0.5), front: biome == .meadow, scale: 0.8)
        }
    }

    /// A trunk up from the ground and branches off it, each a leap up
    /// from the last, and a vine down from the lid to the highest.
    private mutating func canopy() {
        let trunk: HabitatItemKind
        switch biome {
        case .jungle: trunk = .bamboo
        case .desert: trunk = .cactus
        default: trunk = .corkBark
        }
        let tall: CGFloat = trunk == .cactus ? 2.6 : (trunk == .bamboo ? 2.6 * lift : 2.9 * lift)
        put(trunk, at(0.16), scale: trunk == .corkBark ? 1.45 : 1.2, tall: tall)
        let b1 = 190 * lift, b2 = 400 * lift, b3 = 610 * lift, b4 = 820 * lift
        put(.branch, at(0.34), b1, scale: 1.4, flipped: false)
        put(.branch, at(0.58), b2, scale: 1.5, flipped: true)
        put(.branch, at(0.82), b3, scale: 1.35, flipped: false)
        put(.branch, at(0.5), b4, scale: 1.3, flipped: true)
        if biome == .desert || biome == .beach {
            put(.driftwood, at(0.5), scale: 1.2)
        } else {
            vine(at(0.7), down: b3 - 40)
            vine(at(0.95), down: b2 + 30)
            vine(at(0.36), down: b4 - 60)
            put(biome == .tundra ? .twigs : .leafPile, at(0.5))
        }
        put(dry ? .succulent : .fern, at(0.05), front: true, scale: 1.1)
    }

    private mutating func shelter() {
        switch biome {
        case .desert:
            put(.boulder, at(0.3), scale: 1.4)
            put(.driftwood, at(0.55), scale: 1.2)
            put(.rock, at(0.75))
            put(.succulent, at(0.9), front: true)
        case .beach:
            put(.driftwood, at(0.3), scale: 1.5)
            put(.boulder, at(0.62), scale: 1.1)
            put(.driftwood, at(0.62), 92, scale: 1.1)
            put(.pebbles, at(0.85))
        case .cave:
            put(.boulder, at(0.25), scale: 1.5)
            put(.corkBark, at(0.5), tall: 1.4)
            put(.boulder, at(0.75), scale: 1.1)
            put(.mushrooms, at(0.62), scale: 0.9)
        case .tundra:
            put(.log, at(0.3), scale: 1.3)
            put(.boulder, at(0.62), scale: 1.2)
            put(.twigs, at(0.84))
        default:
            put(.hide, at(0.28), scale: 1.25)
            put(.corkBark, at(0.52), scale: 1.2)
            put(.log, at(0.76), scale: 1.2)
            put(.mushrooms, at(0.76), 52, scale: 0.8)
            put(.moss, at(0.1))
            put(.fern, at(0.92), front: true)
        }
    }

    private mutating func pool() {
        put(.waterDish, at(0.36), scale: 1.3)
        put(.waterDish, at(0.64), scale: 0.9)
        put(.pebbles, at(0.18))
        put(.rock, at(0.82), scale: 0.7)
        switch biome {
        case .desert, .beach: put(.succulent, at(0.5), front: true, scale: 0.8)
        case .cave: put(.crystal, at(0.5), scale: 0.8)
        case .tundra: put(.moss, at(0.5))
        default:
            put(.moss, at(0.5))
            put(.grass, at(0.08), scale: 1.1)
            put(biome == .meadow || biome == .jungle ? .flower : .fern, at(0.92), front: true)
        }
    }

    private mutating func rocks() {
        let big = put(.boulder, at(0.28), scale: dice.range(1.3, 1.6))
        put(.rock, at(0.48))
        put(.boulder, at(0.68), scale: dice.range(0.9, 1.1))
        put(.rock, at(0.85), scale: 0.6)
        put(.pebbles, at(0.12))
        // Something propped on top of the big one.
        if let top = Habitat.solidRect(big)?.maxY {
            put(biome == .desert || biome == .beach ? .driftwood : .log, big.x + big.w * 0.1, top - HabitatLayout.ground, scale: 0.8)
        }
        switch biome {
        case .desert: put(.cactus, at(0.58), scale: 0.7)
        case .cave: put(.crystal, at(0.58), scale: 1.2); put(.crystal, at(0.94), front: true, scale: 0.7)
        case .tundra: put(.moss, at(0.58))
        case .beach: put(.twigs, at(0.58))
        default: put(.moss, at(0.58)); put(.mushrooms, at(0.94), scale: 0.8)
        }
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

    /// Everything it can walk on, in world points — offset by `origin`
    /// (the tools lay a world out somewhere on a mock desktop): one closed
    /// loop round the inside of the tank — along the ground and up and over
    /// whatever stands on it, up the glass, across under the lid and back
    /// down — and a loop of its own for anything off the ground (a branch,
    /// a vine, the leafy top of a plant). Built once for the layout: the
    /// camera moving about the world never changes any of it.
    func surfaces(at origin: CGPoint = .zero, standoff off: CGFloat) -> (air: CGRect, loops: [SurfaceLoop]) {
        let scene = CGRect(origin: origin, size: size)
        func toScreen(_ r: CGRect) -> CGRect { r.offsetBy(dx: origin.x, dy: origin.y) }
        func pt(_ p: V2) -> V2 { V2(origin.x + p.x, origin.y + p.y) }
        let groundY = scene.minY + HabitatLayout.ground
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

        let floor = Habitat.skyline(blocks, from: inner.minX, to: inner.maxX, feetFrom: air.minX, feetTo: air.maxX,
                                    base: groundY, standoff: off, ceiling: inner.maxY - 24)
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
    /// The body's line runs `x0`…`x1`, stood off the walls; the ground its
    /// feet go on runs `feetFrom`…`feetTo`, right up to the glass, so a
    /// foot in a bottom corner has the floor under it.
    static func skyline(_ blocks: [CGRect], from x0: CGFloat, to x1: CGFloat, feetFrom: CGFloat, feetTo: CGFloat,
                        base: CGFloat, standoff off: CGFloat,
                        ceiling: CGFloat) -> (segs: [Seg], edge: [Seg], heights: [CGFloat]) {
        // The body's line: each block grown by the body's height.
        func profile(_ rects: [CGRect], lift: CGFloat, grow: CGFloat, from x0: CGFloat, to x1: CGFloat) -> [(x0: CGFloat, x1: CGFloat, y: CGFloat)] {
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
        let body = profile(blocks, lift: off, grow: off, from: x0, to: x1)
        let feet = profile(blocks, lift: 0, grow: 0, from: feetFrom, to: feetTo)
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
