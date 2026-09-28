import AppKit

// MARK: - What each kind of thing is
//
// Everything about a kind of thing in the tank that is not its picture
// lives in its definition, in one place: what it is called, which part of
// the picker it goes in, how big it comes, where it may be put, how it
// moves in the air, and — most of all — its physical shape: the parts of
// it the spider can really hold on to (see HabitatGeometry.swift).
//
// Adding a kind of thing: a case below, its definition in `definition`,
// its shape (built from the same paths its picture is painted from, in
// `HabitatShape`), and its picture in `HabitatArt.paintItem`. The compiler
// asks for each in turn. `tools/perch.sh sheet` draws every kind with its
// shape over its picture, to check the two agree.

/// Things to put in the habitat. Some are furniture it can climb on; some
/// are just scenery.
enum HabitatItemKind: String, Codable, CaseIterable {
    // Perches, in the order the picker shows them.
    case log, branch, driftwood, corkBark, hide, rock, boulder, bamboo, cactus, plant, vine, waterDish
    // Plants and details.
    case fern, grass, flower, succulent, mushrooms, moss, leafPile, pebbles, twigs, crystal

    var definition: HabitatObjectDefinition {
        typealias D = HabitatObjectDefinition
        switch self {
        case .log: return D("Log", .perch, 180, 50, .rests, shape: HabitatShape.log)
        case .branch: return D("Branch", .perch, 230, 130, .wedged, shape: HabitatShape.branch)
        case .driftwood: return D("Driftwood", .perch, 200, 56, .rests, shape: HabitatShape.driftwood)
        case .corkBark: return D("Cork Bark", .perch, 74, 210, .ground, shadow: 0.8, shape: HabitatShape.corkBark)
        case .hide: return D("Hollow Log", .perch, 130, 66, .ground, shape: HabitatShape.hollowLog)
        case .rock: return D("Rock", .perch, 76, 44, .ground, shape: HabitatShape.rock)
        case .boulder: return D("Boulder", .perch, 140, 92, .ground, shape: HabitatShape.rock)
        case .bamboo: return D("Bamboo", .perch, 60, 250, .ground, sway: 0.012, windLean: 0.035, shadow: 0.8, shape: HabitatShape.bamboo)
        case .cactus: return D("Cactus", .perch, 70, 150, .ground, shadow: 0.8, shape: HabitatShape.cactus)
        case .plant: return D("Leafy Plant", .perch, 120, 150, .ground, sway: 0.018, windLean: 0.05, shadow: 0.5, shape: HabitatShape.plant)
        case .vine: return D("Hanging Vine", .perch, 40, 230, .hangs, sway: 0.05, windLean: 0.14, shape: HabitatShape.vine)
        case .waterDish: return D("Water Dish", .perch, 96, 26, .ground, shape: HabitatShape.waterDish)
        case .fern: return D("Fern", .scenery, 130, 90, .rests, sway: 0.035, windLean: 0.1, shadow: 0.6, shape: HabitatShape.fern)
        case .grass: return D("Tall Grass", .scenery, 90, 84, .rests, sway: 0.035, windLean: 0.16, shadow: 0.6, shape: HabitatShape.grass)
        case .flower: return D("Flowers", .scenery, 80, 80, .rests, sway: 0.035, windLean: 0.13, shadow: 0.6, shape: HabitatShape.flowers)
        case .succulent: return D("Succulent", .scenery, 64, 46, .rests, shape: HabitatShape.succulent)
        case .mushrooms: return D("Mushrooms", .scenery, 66, 46, .rests, shape: HabitatShape.mushrooms)
        case .moss: return D("Moss", .scenery, 120, 24, .rests, shape: HabitatShape.groundCover)
        case .leafPile: return D("Leaf Litter", .scenery, 130, 26, .rests, shape: HabitatShape.groundCover)
        case .pebbles: return D("Pebbles", .scenery, 90, 20, .rests, shape: HabitatShape.groundCover)
        case .twigs: return D("Twigs", .scenery, 96, 30, .rests, shape: HabitatShape.groundCover)
        case .crystal: return D("Crystals", .scenery, 64, 70, .rests, shape: HabitatShape.crystals)
        }
    }

    var label: String { definition.label }

    /// Climbable, or just to look at.
    var climbable: Bool { definition.category == .perch }

    /// Size in world points (the same as the screen's).
    var defaultSize: CGSize { definition.size }

    /// Hangs from the lid rather than standing on the ground.
    var hangs: Bool { definition.placement == .hangs }

    /// May be put up off the ground: what is propped on or rests on other
    /// things. Rocks and pots and the like stand on the ground.
    var liftable: Bool { definition.placement == .rests || definition.placement == .wedged }

    /// Moves on its own — sways in the air of the tank.
    var sways: Bool { definition.sway > 0 }

    /// Where it goes by default: low things and foliage can go in front of
    /// the spider; furniture it climbs is always behind it.
    var canGoInFront: Bool { !climbable }
}

/// A kind of thing in the tank: everything about it but its picture.
struct HabitatObjectDefinition {
    /// Which part of the picker it goes in.
    enum Category {
        /// Furniture: it has parts the spider can climb.
        case perch
        /// To look at: plants and details it walks past or through.
        case scenery
    }

    /// Where it may be put.
    enum Placement {
        /// On the ground, always.
        case ground
        /// Anywhere; let go of up in the air, it comes to rest on whatever
        /// is under it.
        case rests
        /// Anywhere, and it stays where it is put (a branch, wedged).
        case wedged
        /// From the lid.
        case hangs
    }

    var label: String
    var category: Category
    /// The size it comes in, in world points.
    var size: CGSize
    var placement: Placement
    /// How far it sways to and fro on its own, as a shear (0: it doesn't).
    var sway: CGFloat
    /// How far it leans over in a gale, as a shear.
    var windLean: CGFloat
    /// How wide its shadow on the ground is, for its width.
    var shadow: CGFloat
    /// Its physical shape, in the world, for a thing standing in `rect`
    /// (unflipped): see `ObjectGeometry`.
    var shape: (_ rect: CGRect, _ seed: Int, _ u: CGFloat) -> ObjectGeometry

    init(_ label: String, _ category: Category, _ w: CGFloat, _ h: CGFloat, _ placement: Placement,
         sway: CGFloat = 0, windLean: CGFloat = 0, shadow: CGFloat = 0.96,
         shape: @escaping (CGRect, Int, CGFloat) -> ObjectGeometry) {
        self.label = label
        self.category = category
        size = CGSize(width: w, height: h)
        self.placement = placement
        self.sway = sway
        self.windLean = windLean
        self.shadow = shadow
        self.shape = shape
    }
}

// MARK: - A thing in the tank

struct HabitatItem: Codable, Equatable, Identifiable {
    /// Its number in this habitat: what the tank's editing, its layers and
    /// its surfaces know it by. Never reused within a habitat.
    var id: Int
    /// Who it is, for good: made once, when it is first put in a tank, and
    /// kept through saving, loading, moving and resizing. What anything that
    /// remembers a particular thing — this log, that stone — holds on to.
    var uid: String
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

    init(id: Int, uid: String = HabitatItem.newUID(), kind: HabitatItemKind, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
         flipped: Bool = false, seed: Int = 0, front: Bool = false) {
        self.id = id
        self.uid = uid
        self.kind = kind
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.flipped = flipped
        self.seed = seed
        self.front = front
    }

    static func newUID() -> String { UUID().uuidString }

    // A habitat saved before things had a `uid` has none: it is given one
    // as it loads (see `Habitat.load`), and kept from then on.
    private enum CodingKeys: String, CodingKey { case id, uid, kind, x, y, w, h, flipped, seed, front }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? ""
        kind = try c.decode(HabitatItemKind.self, forKey: .kind)
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        w = try c.decode(CGFloat.self, forKey: .w)
        h = try c.decode(CGFloat.self, forKey: .h)
        flipped = try c.decodeIfPresent(Bool.self, forKey: .flipped) ?? false
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        front = try c.decodeIfPresent(Bool.self, forKey: .front) ?? false
    }

    /// Its rectangle in the world.
    var rect: CGRect {
        kind.hangs ? CGRect(x: x - w / 2, y: y - h, width: w, height: h)
                   : CGRect(x: x - w / 2, y: HabitatLayout.ground + y, width: w, height: h)
    }

    var onGround: Bool { !kind.hangs && y < 2 }
    var inFront: Bool { front && kind.canGoInFront }

    /// How much bigger or smaller than it comes it is drawn: the unit its
    /// picture's strokes, and the thickness of its parts, go by.
    var unit: CGFloat { HabitatShape.unit(kind, rect) }
}
