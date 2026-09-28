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
    /// What is fastened to what (see HabitatStructures.swift). None in a
    /// habitat saved before things could be.
    var links: [HabitatLink] = []

    init() {}
    init(biome: Biome, world: CGSize) {
        self.biome = biome
        self.world = world
    }

    private enum CodingKeys: String, CodingKey { case biome, items, nextID, world, links }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        biome = try c.decode(Biome.self, forKey: .biome)
        items = try c.decode([HabitatItem].self, forKey: .items)
        nextID = try c.decode(Int.self, forKey: .nextID)
        world = try c.decodeIfPresent(CGSize.self, forKey: .world)
        links = try c.decodeIfPresent([HabitatLink].self, forKey: .links) ?? []
    }

    /// The world's size: the old scene's for a habitat not yet moved into one.
    var size: CGSize { world ?? CGSize(width: HabitatLayout.width, height: HabitatLayout.height) }
    var bounds: CGRect { CGRect(origin: .zero, size: size) }

    static let key = "habitat"

    static func load() -> Habitat {
        guard let data = UserDefaults.standard.data(forKey: key),
              var h = try? JSONDecoder().decode(Habitat.self, from: data) else { return .preset(.forestFloor) }
        var changed = h.giveIdentities()
        if h.world == nil {
            h = h.movedIntoWorld(HabitatLayout.defaultWorld)
            changed = true
        }
        if changed { h.save() }
        h.clampAll()
        h.pruneLinks()
        return h
    }

    /// Gives anything without a `uid` of its own one (a habitat saved before
    /// things had them), and makes sure no two share one. True if it had to.
    @discardableResult
    mutating func giveIdentities() -> Bool {
        var seen = Set<String>()
        var changed = false
        for i in items.indices {
            if items[i].uid.isEmpty || seen.contains(items[i].uid) {
                items[i].uid = HabitatItem.newUID()
                changed = true
            }
            seen.insert(items[i].uid)
        }
        return changed
    }

    /// A thing by its lasting identity.
    func item(uid: String) -> HabitatItem? { items.first { $0.uid == uid } }
    /// A thing by its number in this habitat.
    func item(id: Int) -> HabitatItem? { items.first { $0.id == id } }

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
            // (Hung low — from a branch — it is no longer than will clear the ground.)
            it.y = min(max(it.y, G + 40), H)
            it.h = max(10, min(it.h, it.y - G - 10))
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
            case .forestFloor: return ([.thicket, .shelter, .canopy], [.clearing, .canopy, .pool])
            case .jungleCanopy: return ([.pool, .thicket, .canopy], [.thicket, .shelter, .canopy])
            case .desertScrub: return ([.clearing, .pool, .canopy], [.thicket, .shelter, .rocks])
            case .meadow: return ([.clearing, .pool, .canopy], [.thicket, .shelter, .canopy])
            case .cave: return ([.pool, .rocks, .canopy], [.shelter, .thicket, .rocks])
            case .beach: return ([.pool, .clearing, .rocks], [.rocks, .shelter, .canopy])
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
        b.dress()
        // Nothing left floating: brackets on the back wall under what is up
        // in the air.
        b.h.supportFloating()
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
        b.dress()
        b.h.supportFloating()
        return b.h
    }

    /// Where the side of a thing is, `y` up (world), on its right or left:
    /// the furthest out its solid parts reach at that height.
    static func sideAt(_ it: HabitatItem, y: CGFloat, right: Bool) -> CGFloat? {
        var best: CGFloat?
        for part in it.geometry.parts {
            let o = part.outline
            for i in o.indices {
                let a = o[i], b = o[(i + 1) % o.count]
                guard (a.y - y) * (b.y - y) <= 0, abs(b.y - a.y) > 1e-6 else { continue }
                let x = a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
                if best.map({ right ? x > $0 : x < $0 }) ?? true { best = x }
            }
        }
        return best
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
        func count(_ f: (HabitatItemKind) -> Bool) -> Int { items.filter { f($0.kind) }.count }
        if count({ $0.functions.contains(.water) }) > 0 { return .pool }
        if items.contains(where: { ($0.kind.climbable && $0.y > 150) || (!$0.kind.hangs && $0.h > 350) }) { return .canopy }
        if count({ $0.definition.shelf == .shelter || $0 == .hide || $0 == .corkTunnel }) > 0 { return .shelter }
        if count({ $0.climbable && $0.definition.traits.material == .stone && $0.definition.shelf == .structures }) >= 2 { return .rocks }
        if count({ [.hide, .corkBark, .log, .driftwood, .stump].contains($0) }) >= 2 { return .shelter }
        if count({ $0.definition.shelf == .plants }) >= 3 { return .thicket }
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
        it.uid = HabitatItem.newUID()
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
    /// these kinds, in turn, each 400–700 across. `open`: nothing either
    /// side to lean on — the first part starts right at `a`.
    mutating func fill(from a: CGFloat, to b: CGFloat, kinds: [HabitatRegion.Kind], open: Bool = false) {
        let span = abs(b - a)
        guard span > 200, !kinds.isEmpty else { return }
        let n = open ? kinds.count : max(1, Int((span / 540).rounded()))
        // With room for fewer than there are, the one by the glass is kept.
        let laid = n >= kinds.count ? (0..<n).map { kinds[$0 % kinds.count] } : Array(kinds.prefix(n - 1)) + [kinds.last!]
        let dir: CGFloat = b > a ? 1 : -1
        for (k, kind) in laid.enumerated() {
            let lo = a + dir * span * CGFloat(k) / CGFloat(n), hi = a + dir * span * CGFloat(k + 1) / CGFloat(n)
            region(kind, from: min(lo, hi), to: max(lo, hi))
        }
    }

    // MARK: The parts
    //
    // Each part has a character of its own — dense planting, open ground
    // with litter to hunt over, branches up into the air, somewhere to hide,
    // water, rock — in whatever grows in this scenery (see each kind's
    // `traits.suits`). Nothing is labelled: they are just different places.

    private var dry: Bool { biome == .desert || biome == .beach }
    private var green: Bool { [.forest, .jungle, .meadow, .night].contains(biome) }

    /// The part being laid out: where it starts, and how wide it is.
    private var partX: CGFloat = 0, partW: CGFloat = 0

    /// A fraction of the way across the part, give or take a little.
    private mutating func at(_ f: CGFloat) -> CGFloat { partX + partW * f + dice.range(-1, 1) * partW * 0.03 }

    /// One of these, picked (the first that suits the scenery, if any does).
    private mutating func any(_ kinds: [HabitatItemKind]) -> HabitatItemKind {
        let fit = kinds.filter { $0.suits(biome) }
        return dice.pick(fit.isEmpty ? kinds : fit)
    }

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

    /// Dense planting: somewhere to hide and lie in wait.
    private mutating func thicket() {
        switch biome {
        case .desert:
            put(.cactus, at(0.2), scale: dice.range(1.2, 1.6))
            put(.aloe, at(0.34), scale: dice.range(1, 1.3))
            put(.jadePlant, at(0.5), scale: 1.2)
            put(.cactus, at(0.72), scale: dice.range(1.5, 2))
            put(.deadPlant, at(0.86), scale: 1.2)
            put(.lithops, at(0.42))
            put(.sandDrift, at(0.62), scale: 0.8)
            put(.succulent, at(0.1), front: true, scale: 0.9)
            put(.gravel, at(0.9), front: true)
        case .beach:
            put(.miniPalm, at(0.16), scale: 1.3)
            put(.grassClump, at(0.3), scale: 1.2)
            put(.driftwoodBranch, at(0.5), scale: 0.9)
            put(.grassClump, at(0.68), scale: 1.4)
            put(.aloe, at(0.84))
            put(.seaShell, at(0.42), scale: 0.8)
            put(.sandDrift, at(0.76))
            put(.grass, at(0.6), front: true, scale: 1.1)
        case .cave:
            put(.crystalCluster, at(0.2), scale: 1.2)
            put(.mushroomCluster, at(0.36), scale: 1.1)
            put(.largeFern, at(0.54), scale: 0.9)
            put(.crystalCluster, at(0.78), scale: 0.8)
            put(.hangingRoots, at(0.45), tall: 1.5 * lift)
            put(.glowMushrooms, at(0.64))
            put(.glowMushrooms, at(0.92), scale: 0.8)
            put(.smallFern, at(0.1), front: true)
        case .tundra:
            put(.stump, at(0.24), scale: 1.1)
            put(.grassClump, at(0.12), scale: 0.9)
            put(.deadPlant, at(0.44), scale: 1.2)
            put(.grassClump, at(0.6))
            put(.mossCushion, at(0.74))
            put(.pineCone, at(0.84))
            put(.pineNeedles, at(0.5))
            put(.grass, at(0.66), front: true, scale: 0.8)
        default:
            // A thick stand of plants under the arch of a big fern, a vine
            // climbing through it, foliage trailing down from above.
            put(biome == .meadow ? .floweringPlant : .largeFern, at(0.18), scale: dice.range(1.1, 1.3))
            put(biome == .jungle ? .leafCanopy : .broadLeaf, at(0.38), scale: dice.range(1.1, 1.3))
            put(.climbingVine, at(0.5), tall: dice.range(1.3, 1.7))
            put(any([.grassClump, .fiddleheads, .floweringPlant]), at(0.62), scale: 1.2)
            put(biome == .meadow ? .floweringPlant : .largeFern, at(0.8), scale: dice.range(1, 1.2))
            put(.mossCushion, at(0.28))
            put(any([.mushroomCluster, .tinyMushrooms, .glowMushrooms]), at(0.7))
            put(biome == .meadow ? .tinyFlowers : .creepingCover, at(0.92))
            put(.hangingFoliage, at(0.3), tall: dice.range(1.2, 1.6) * lift)
            put(.smallFern, at(0.08), front: true, scale: 1.3)
            put(biome == .meadow ? .tinyFlowers : .fern, at(0.72), front: true, scale: 1.1)
        }
    }

    /// Open ground with a little litter on it: somewhere to hunt.
    private mutating func clearing() {
        switch biome {
        case .desert:
            put(.gravel, at(0.2))
            put(.sandDrift, at(0.42), scale: 1.2)
            put(.seedPod, at(0.6))
            put(.baskingStone, at(0.8))
            put(.tinyPebble, at(0.3))
            put(.deadLeaf, at(0.66))
        case .beach:
            put(.sandDrift, at(0.2), scale: 1.3)
            put(.seaShell, at(0.44))
            put(.smallShell, at(0.56))
            put(.feather, at(0.68))
            put(.pebblePile, at(0.84), scale: 0.8)
            put(.smallShell, at(0.3), front: true)
        case .cave:
            put(.gravel, at(0.2))
            put(.puddle, at(0.45), scale: 1.2)
            put(.pebblePile, at(0.7))
            put(.tinyMushrooms, at(0.86))
            put(.crystal, at(0.6), scale: 0.6)
        case .tundra:
            put(.pineNeedles, at(0.2))
            put(.smoothStones, at(0.4), scale: 0.9)
            put(.twigPile, at(0.62), scale: 0.8)
            put(.pineCone, at(0.8))
            put(.tinyTwig, at(0.5))
        default:
            put(biome == .meadow ? .tinyFlowers : .leafPile, at(0.16))
            put(.fallenLeaf, at(0.3))
            put(any([.acorn, .snailShell, .seedPod]), at(0.4))
            put(biome == .meadow ? .creepingCover : .pineNeedles, at(0.55))
            put(dice.chance(0.5) ? .mushroom : .puddle, at(0.66))
            put(.rock, at(0.82), scale: 0.7)
            put(biome == .meadow ? .petals : .looseLeaf, at(0.74))
            put(any([.deadLeaf, .feather, .seed]), at(0.92))
            put(biome == .meadow ? .grass : .smallFern, at(0.5), front: true, scale: 0.8)
        }
    }

    /// Branches up into the air of the tank: uprights, and branches laid
    /// from the top of one to the next, so each holds the next up; things
    /// hanging from above to climb down, and roots at the foot.
    private mutating func canopy() {
        let G = HabitatLayout.ground
        // The uprights, each taller than the last.
        let choices: [HabitatItemKind]
        switch biome {
        case .jungle: choices = [.bambooTipi, .threeFork, .lookout, .bambooTipi, .climbingRoot]
        case .desert: choices = [.rockSpire, .driftwoodSnag, .lookout]
        case .beach: choices = [.driftwoodSnag, .lookout, .rockSpire]
        case .cave: choices = [.rockSpire, .lookout, .rockSpire]
        default: choices = [.threeFork, .corkBark, .lookout, .climbingRoot]
        }
        // (A different stand each time: no two alike.)
        var uprights: [HabitatItemKind] = []
        while uprights.count < 3 {
            let k = dice.pick(choices)
            if uprights.last != k || choices.count < 2 { uprights.append(k) }
        }
        if !uprights.contains(.lookout), choices.contains(.lookout), dice.chance(0.6) { uprights[2] = .lookout }
        let heights: [CGFloat] = [260 * lift, 470 * lift, 680 * lift]
        let xs: [CGFloat] = [at(0.14), at(0.48), at(0.84)]
        var tops: [V2] = []
        for (i, kind) in uprights.enumerated() {
            let it = put(kind, xs[i], scale: kind == .corkBark ? 1.3 : 1.1, tall: heights[i] / kind.defaultSize.height, flipped: false)
            // Where a branch rests on it: its top, or a fork's crotch.
            let top = kind == .threeFork ? V2(it.x, it.rect.minY + it.h * 0.62)
                : kind == .climbingRoot ? V2(it.x, it.rect.maxY - it.h * 0.25) : V2(it.x, it.rect.maxY - (kind == .lookout ? 4 : 10))
            tops.append(top)
        }
        // Branches from one top to the next.
        for i in 0..<2 { bridge(from: tops[i], to: tops[i + 1]) }
        // And one out from the tallest, up toward the lid.
        let hi = tops[2]
        bridge(from: V2(hi.x - partW * 0.02, hi.y - 8), to: V2(min(hi.x + partW * 0.22, W - 80), hi.y + 130 * lift))
        // Things to climb down from above.
        if biome == .desert || biome == .beach {
            put(.driftwoodRoot, at(0.3), scale: 1.1)
        } else {
            put(any([.hangingFoliage, .hangingRoots, .vine]), at(0.66), tall: (H - G - tops[1].y + G - 60) / 240)
            put(any([.hangingLeafShelter, .hangingBranch]), at(0.32), tall: 1.4 * lift)
            vine(at(0.96), down: tops[2].y - G + 40)
            put(biome == .tundra ? .pineNeedles : .leafPile, at(0.56))
            put(any([.exposedRoot, .rootTangle]), at(0.28), scale: 0.9)
        }
        put(dry ? .succulent : .fern, at(0.04), front: true, scale: 1.1)
    }

    /// A branch laid from `p` to `q` (both world points it rests on), long
    /// enough to overhang each a little: flat, or rising.
    private mutating func bridge(from p: V2, to q: V2) {
        let G = HabitatLayout.ground
        let dx = abs(q.x - p.x), dy = q.y - p.y
        let left = p.x < q.x ? p : q, right = p.x < q.x ? q : p
        if abs(dy) < 60 {
            // Flat: a twisted branch across, its middle line through both.
            let kind: HabitatItemKind = biome == .jungle ? .bambooSegment : (dice.chance(0.5) ? .twistedBranch : .shortBranch)
            let w = dx + 70
            let hgt = kind.defaultSize.height * (kind == .bambooSegment ? 1 : 1.1)
            let mid = kind == .twistedBranch ? 0.46 : (kind == .shortBranch ? 0.5 : 0.5)
            let y = (left.y + right.y) / 2 - hgt * mid - G
            var it = put(kind, (left.x + right.x) / 2, max(0, y), flipped: false)
            it.w = w
            it.h = hgt
            h.items[h.items.count - 1] = it
        } else {
            // Rising: a medium branch, its line from low end to tip (2% to 98%
            // across, 25% to 80% up) laid from one to the other.
            let kind: HabitatItemKind = dry ? .driftwoodBranch : .mediumBranch
            let (lx, ly, rx, ry): (CGFloat, CGFloat, CGFloat, CGFloat) = kind == .mediumBranch ? (0.02, 0.25, 0.98, 0.8) : (0.02, 0.03, 0.98, 0.9)
            let low = left.y < right.y ? left : right, high = left.y < right.y ? right : left
            let w = (dx + 50) / (rx - lx), hgt = abs(dy) / (ry - ly)
            let flip = low.x > high.x
            let cx = (low.x + high.x) / 2
            let y = low.y - ly * hgt - G
            var it = put(kind, cx, max(0, y), flipped: flip)
            it.w = w
            it.h = max(hgt, 40)
            it.x = cx
            it.y = max(0, y)
            Habitat.clamp(&it, in: h.size)
            h.items[h.items.count - 1] = it
        }
    }

    /// Somewhere to shelter: two places it can get right inside, set apart
    /// with their ways in facing the open ground between them (never one
    /// across the other's mouth), and what lies about them.
    private mutating func shelter() {
        func pair(_ a: HabitatItemKind, flip fa: Bool, _ b: HabitatItemKind, flip fb: Bool) {
            put(a, at(0.24), flipped: fa)
            put(b, at(0.77), flipped: fb)
        }
        switch biome {
        case .desert:
            pair(.overhang, flip: false, .rockCrevice, flip: false)
            put(.aloe, at(0.02))
            put(.gravel, at(0.5))
            put(.deadPlant, at(0.97), scale: 0.8)
        case .beach:
            pair(.driftwoodRoot, flip: false, .overhang, flip: true)
            put(.seaShell, at(0.5), scale: 0.8)
            put(.smallShell, at(0.56))
        case .cave:
            pair(.rockCrevice, flip: true, .mossyHide, flip: true)
            put(.glowMushrooms, at(0.5))
            put(.puddle, at(0.97), scale: 0.7)
        case .tundra:
            pair(.logDen, flip: true, .rootHollow, flip: false)
            put(.pineCone, at(0.5))
            put(.pineNeedles, at(0.55))
        default:
            // A bark cave or a curled leaf, and a hollow log or a hollow
            // under a stump's roots.
            let first: HabitatItemKind = biome == .jungle || biome == .meadow ? .curledLeafHide : .barkCave
            let second: HabitatItemKind = dice.chance(0.5) ? .logDen : .rootHollow
            // (A log den's way in is at its left end; the others' at their right.)
            pair(first, flip: false, second, flip: second != .logDen)
            put(.leafPile, at(0.5))
            put(.shedBark, at(0.03), scale: 0.8)
            put(.fern, at(0.98), front: true)
        }
    }

    /// Water, and what grows by it.
    private mutating func pool() {
        put(biome == .cave || biome == .tundra ? .rockPool : .waterDish, at(0.36), scale: 1.3)
        put(dice.chance(0.5) ? .rockPool : .puddle, at(0.64), scale: 0.9)
        put(.smoothStones, at(0.18), scale: 0.8)
        switch biome {
        case .desert, .beach:
            put(.aloe, at(0.84))
            put(biome == .beach ? .seaShell : .baskingStone, at(0.5), scale: 0.8)
            put(.succulent, at(0.5), front: true, scale: 0.8)
        case .cave:
            put(.glowMushrooms, at(0.5))
            put(.crystalCluster, at(0.84), scale: 0.7)
        case .tundra:
            put(.mossCushion, at(0.52))
            put(.pebblePile, at(0.84))
        default:
            put(.moistMoss, at(0.52))
            put(.broadLeaf, at(0.84), scale: 1.1)
            put(.snailShell, at(0.1))
            put(.grass, at(0.06), scale: 1.1)
            put(biome == .meadow || biome == .jungle ? .flower : .smallFern, at(0.92), front: true)
        }
    }

    /// Stone: boulders, a spire or an arch, and a warm flat stone to sit on.
    private mutating func rocks() {
        let big = put(.boulder, at(0.24), scale: dice.range(1.3, 1.6))
        put(biome == .desert || biome == .cave || biome == .beach ? .stoneArch : .rock, at(0.5))
        put(.boulder, at(0.76), scale: dice.range(0.9, 1.1))
        put(.baskingStone, at(0.92), scale: 0.8)
        put(.pebblePile, at(0.1))
        // Something propped on top of the big one, resting on the top of it.
        let prop: HabitatItemKind = biome == .desert || biome == .beach ? .driftwood : .log
        let px = big.x + big.w * 0.1, half = prop.defaultSize.width * 0.8 * 0.25
        if let top = Habitat.restingTop(big, from: px - half, to: px + half) {
            put(prop, px, top - HabitatLayout.ground, scale: 0.8)
        }
        switch biome {
        case .desert: put(.cactus, at(0.62), scale: 0.7)
        case .cave: put(.crystalCluster, at(0.62)); put(.crystal, at(0.96), front: true, scale: 0.7)
        case .tundra: put(.smoothStones, at(0.62))
        case .beach: put(.seaShell, at(0.62))
        default: put(.mossCushion, at(0.62)); put(.mushrooms, at(0.96), scale: 0.8)
        }
    }

    // MARK: Dressing

    /// Small things where they would grow or lie: fungus on the side of a
    /// stump or a slab of bark, lichen on stone, mushrooms and moss on a
    /// log — for each thing some suit, now and then.
    mutating func dress() {
        let hosts = h.items.filter { !$0.kind.hangs && $0.kind.climbable && $0.onGround && $0.w > 60 }
        for host in hosts {
            let m = host.kind.definition.traits.material
            // What grows on this, in this scenery.
            let onTop = HabitatItemKind.allCases.filter { k in
                let n = k.definition.traits.niche
                return !n.side && n.on.contains(m) && k.suits(biome) && k.definition.shelf == .details && k.definition.size.width < host.w * 0.6
            }
            let onSide = HabitatItemKind.allCases.filter { k in
                let n = k.definition.traits.niche
                return n.side && n.on.contains(m) && k.suits(biome)
            }
            if !onSide.isEmpty, host.h > 70, dice.chance(0.45) {
                // Out of its side, part way up.
                let k = dice.pick(onSide)
                let right = dice.chance(0.5)
                let y = host.h * dice.range(0.3, 0.6)
                let edge = Habitat.sideAt(host, y: host.rect.minY + y, right: right) ?? (right ? host.rect.maxX : host.rect.minX)
                let w = k.defaultSize.width
                put(k, edge + (right ? w * 0.5 - 4 : -w * 0.5 + 4), y, flipped: !right)
            }
            if !onTop.isEmpty, dice.chance(0.35) {
                let k = dice.pick(onTop)
                let x = host.x + host.w * dice.range(-0.25, 0.25)
                let half = k.defaultSize.width * 0.8 * 0.25
                if let top = Habitat.restingTop(host, from: x - half, to: x + half) {
                    put(k, x, top - HabitatLayout.ground, scale: 0.8)
                }
            }
        }
    }
}
