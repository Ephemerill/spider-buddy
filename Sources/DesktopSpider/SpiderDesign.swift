import AppKit
import CoreGraphics

// MARK: - Appearance
//
// Everything the studio can change about how the spider looks. Each part is an
// enum so the options can be listed, thumbnailed and stored by name. The
// renderer reads these every frame; nothing here changes the rig's topology,
// so every option works with every animation.

enum BodyShape: String, Codable, CaseIterable {
    case classic, round, plump, slim, peanut, chonk, tall, pear, bighead, bean, petite
    /// Shaped by hand: the look's `bodyTune` gives the measurements.
    case custom
    var label: String {
        switch self {
        case .custom: return "Custom"
        case .classic: return "Classic"
        case .round: return "Round"
        case .plump: return "Plump"
        case .slim: return "Slim"
        case .peanut: return "Peanut"
        case .chonk: return "Chonk"
        case .tall: return "Tall"
        case .pear: return "Pear"
        case .bighead: return "Big Head"
        case .bean: return "Bean"
        case .petite: return "Petite"
        }
    }
    /// Multipliers on the abdomen (rx, ry) and head radius.
    var metrics: (arx: CGFloat, ary: CGFloat, head: CGFloat) {
        switch self {
        case .classic: return (1.0, 1.0, 1.0)
        case .round: return (1.08, 1.1, 1.04)
        case .plump: return (1.22, 1.16, 0.96)
        case .slim: return (0.95, 0.82, 0.92)
        case .peanut: return (0.82, 0.86, 1.1)
        case .chonk: return (1.3, 1.26, 1.12)
        case .tall: return (0.9, 1.18, 1.0)
        case .pear: return (1.12, 1.3, 0.8)
        case .bighead: return (0.82, 0.84, 1.3)
        case .bean: return (1.28, 0.78, 0.88)
        case .petite: return (0.84, 0.84, 0.86)
        case .custom: return (1.0, 1.0, 1.0)
        }
    }
}

/// A body shaped by hand: multipliers on the abdomen's width and height and
/// the head's size, each around 1.
struct BodyTune: Codable, Hashable {
    var width: CGFloat = 1
    var height: CGFloat = 1
    var head: CGFloat = 1
    static let widthRange: ClosedRange<CGFloat> = 0.7...1.4
    static let heightRange: ClosedRange<CGFloat> = 0.7...1.4
    static let headRange: ClosedRange<CGFloat> = 0.7...1.4
}

enum EyeStyle: String, Codable, CaseIterable {
    case classic, huge, beady, sleepy, wide, sparkly, oval, cross, wink, glowing, dizzy, hearts, button
    /// Shaped by hand: the look's `eyeTune` gives the measurements.
    case custom
    var label: String {
        switch self {
        case .custom: return "Custom"
        case .classic: return "Classic"
        case .huge: return "Huge"
        case .beady: return "Beady"
        case .sleepy: return "Sleepy"
        case .wide: return "Wide"
        case .sparkly: return "Sparkly"
        case .oval: return "Oval"
        case .cross: return "Cross-eyed"
        case .wink: return "Wink"
        case .glowing: return "Glowing"
        case .dizzy: return "Dizzy"
        case .hearts: return "Heart Eyes"
        case .button: return "Button"
        }
    }
    var sizeMul: CGFloat {
        switch self {
        case .huge: return 1.22
        case .beady: return 0.7
        case .wide: return 1.08
        case .button: return 1.1
        default: return 1
        }
    }
    /// Resting eyelid, 0..1.
    var lid: CGFloat { self == .sleepy ? 0.42 : 0 }
    /// Vertical squash for oval eyes.
    var squash: CGFloat { self == .oval ? 1.25 : 1 }
}

/// Eyes shaped by hand: how big, how tall (taller than wide past 1, wider
/// than tall under it), how far apart across the face, and how heavy the
/// lids sit.
struct EyeTune: Codable, Hashable {
    var size: CGFloat = 1
    var height: CGFloat = 1
    var spread: CGFloat = 1
    var lids: CGFloat = 0
    static let sizeRange: ClosedRange<CGFloat> = 0.6...1.4
    static let heightRange: ClosedRange<CGFloat> = 0.7...1.4
    static let spreadRange: ClosedRange<CGFloat> = 0.8...1.2
    static let lidsRange: ClosedRange<CGFloat> = 0...0.6
}

enum BrowStyle: String, Codable, CaseIterable {
    case none, soft, arched, stern, worried, unibrow, thick, quizzical, bushy, flat
    var label: String {
        switch self {
        case .none: return "None"
        case .soft: return "Soft"
        case .arched: return "Arched"
        case .stern: return "Stern"
        case .worried: return "Worried"
        case .unibrow: return "Unibrow"
        case .thick: return "Thick"
        case .quizzical: return "Quizzical"
        case .bushy: return "Bushy"
        case .flat: return "Flat"
        }
    }
}

enum FangStyle: String, Codable, CaseIterable {
    case none, tiny, big, tusks, emerald, smile, blep, grin, frown, buckTeeth, open
    var label: String {
        switch self {
        case .none: return "None"
        case .tiny: return "Tiny"
        case .big: return "Big"
        case .tusks: return "Tusks"
        case .emerald: return "Emerald"
        case .smile: return "Smile"
        case .blep: return "Blep"
        case .grin: return "Grin"
        case .frown: return "Frown"
        case .buckTeeth: return "Buck Teeth"
        case .open: return "Gasp"
        }
    }
}

enum LegStyle: String, Codable, CaseIterable {
    case classic, slender, chunky, stubby, long, fuzzy, banded, socks, spindly, boots, robot, knobbly, striped
    /// Shaped by hand: the look's `legTune` gives the measurements.
    case custom
    var label: String {
        switch self {
        case .custom: return "Custom"
        case .classic: return "Classic"
        case .slender: return "Slender"
        case .chunky: return "Chunky"
        case .stubby: return "Stubby"
        case .long: return "Long"
        case .fuzzy: return "Fuzzy"
        case .banded: return "Banded"
        case .socks: return "Socks"
        case .spindly: return "Spindly"
        case .boots: return "Boots"
        case .robot: return "Robot"
        case .knobbly: return "Knobbly"
        case .striped: return "Striped"
        }
    }
    /// Width multiplier, horizontal reach multiplier, and extra knee height.
    var metrics: (width: CGFloat, reach: CGFloat, knee: CGFloat) {
        switch self {
        case .classic: return (1.0, 1.0, 0)
        case .slender: return (0.72, 1.06, 1)
        case .chunky: return (1.35, 0.96, -1)
        case .stubby: return (1.15, 0.78, -3)
        case .long: return (0.9, 1.24, 5)
        case .fuzzy: return (1.05, 1.0, 0)
        case .banded: return (1.0, 1.0, 0)
        case .socks: return (1.0, 1.0, 0)
        case .spindly: return (0.55, 1.32, 8)
        case .boots: return (1.0, 0.98, 0)
        case .robot: return (1.1, 1.0, 1)
        case .knobbly: return (0.9, 1.02, 2)
        case .striped: return (1.0, 1.0, 0)
        case .custom: return (1.0, 1.0, 0)
        }
    }
}

/// Legs shaped by hand: how thick, how far they reach, and how high the
/// knees stand.
struct LegTune: Codable, Hashable {
    var width: CGFloat = 1
    var reach: CGFloat = 1
    var knee: CGFloat = 0
    static let widthRange: ClosedRange<CGFloat> = 0.5...1.5
    static let reachRange: ClosedRange<CGFloat> = 0.7...1.35
    static let kneeRange: ClosedRange<CGFloat> = -4...10
}

enum Pattern: String, Codable, CaseIterable {
    case plain, stripe, spots, chevron, heart, star, saddle, bands, diamond
    case speckle, zigzag, skull, moon, flower, eyespots, hourglass, tiger, leopard, checker, lightning
    var label: String {
        switch self {
        case .plain: return "Plain"
        case .stripe: return "Stripe"
        case .spots: return "Spots"
        case .chevron: return "Chevron"
        case .heart: return "Heart"
        case .star: return "Star"
        case .saddle: return "Saddle"
        case .bands: return "Bands"
        case .diamond: return "Diamond"
        case .speckle: return "Speckle"
        case .zigzag: return "Zigzag"
        case .skull: return "Skull"
        case .moon: return "Moon"
        case .flower: return "Flower"
        case .eyespots: return "Eyespots"
        case .hourglass: return "Hourglass"
        case .tiger: return "Tiger"
        case .leopard: return "Leopard"
        case .checker: return "Checker"
        case .lightning: return "Lightning"
        }
    }
}

enum Hat: String, Codable, CaseIterable {
    case none, topHat, partyHat, crown, beanie, flower, bow, cap, halo, wizard, propeller
    case cowboy, chef, bucket, viking, tiara, pirate, mushroom
    case sombrero, fez, beret, bowler, santa, gradCap, bunnyEars, catEars, antlers, hardHat
    case sailor, jester, devilHorns, unicorn, ushanka, pumpkin, strawberry, sweatband, flowerCrown, bird
    var label: String {
        switch self {
        case .none: return "None"
        case .topHat: return "Top Hat"
        case .partyHat: return "Party Hat"
        case .crown: return "Crown"
        case .beanie: return "Beanie"
        case .flower: return "Flower"
        case .bow: return "Bow"
        case .cap: return "Cap"
        case .halo: return "Halo"
        case .wizard: return "Wizard"
        case .propeller: return "Propeller"
        case .cowboy: return "Cowboy"
        case .chef: return "Chef"
        case .bucket: return "Bucket Hat"
        case .viking: return "Viking"
        case .tiara: return "Tiara"
        case .pirate: return "Pirate"
        case .mushroom: return "Mushroom"
        case .sombrero: return "Sombrero"
        case .fez: return "Fez"
        case .beret: return "Beret"
        case .bowler: return "Bowler"
        case .santa: return "Santa"
        case .gradCap: return "Graduate"
        case .bunnyEars: return "Bunny Ears"
        case .catEars: return "Cat Ears"
        case .antlers: return "Antlers"
        case .hardHat: return "Hard Hat"
        case .sailor: return "Sailor"
        case .jester: return "Jester"
        case .devilHorns: return "Horns"
        case .unicorn: return "Unicorn"
        case .ushanka: return "Ushanka"
        case .pumpkin: return "Pumpkin"
        case .strawberry: return "Strawberry"
        case .sweatband: return "Sweatband"
        case .flowerCrown: return "Flower Crown"
        case .bird: return "Little Bird"
        }
    }
}

enum Accessory: String, Codable, CaseIterable {
    case none, glasses, monocle, bowTie, scarf, headphones, bandana, backpack, sunglasses
    case cape, satchel, collar, necktie, wings, lei
    case moustache, beard, eyepatch, goggles, heartShades, mask, clownNose
    case pearls, medal, sweater, tutu, balloon, jetpack, batWings, bindle
    var label: String {
        switch self {
        case .none: return "None"
        case .glasses: return "Glasses"
        case .monocle: return "Monocle"
        case .bowTie: return "Bow Tie"
        case .scarf: return "Scarf"
        case .headphones: return "Headphones"
        case .bandana: return "Bandana"
        case .backpack: return "Backpack"
        case .sunglasses: return "Shades"
        case .cape: return "Cape"
        case .satchel: return "Satchel"
        case .collar: return "Bell Collar"
        case .necktie: return "Necktie"
        case .wings: return "Fairy Wings"
        case .lei: return "Flower Lei"
        case .moustache: return "Moustache"
        case .beard: return "Beard"
        case .eyepatch: return "Eyepatch"
        case .goggles: return "Goggles"
        case .heartShades: return "Heart Shades"
        case .mask: return "Hero Mask"
        case .clownNose: return "Clown Nose"
        case .pearls: return "Pearls"
        case .medal: return "Medal"
        case .sweater: return "Sweater"
        case .tutu: return "Tutu"
        case .balloon: return "Balloon"
        case .jetpack: return "Jetpack"
        case .batWings: return "Bat Wings"
        case .bindle: return "Bindle"
        }
    }
}

/// Body colourways. Each is a base body tone and a leg tone; the renderer
/// derives highlights, shadows and the outline from them.
enum Coat: String, Codable, CaseIterable {
    case classic, midnight, regal, peacock, rose, moss, snow, lavender, ember, honey, cocoa, ocean, mint, slate
    case cherry, tangerine, lemon, lime, forest, sky, navy, royal, plum, bubblegum, coral, sand, charcoal, copper, olive, ghost
    var label: String {
        switch self {
        case .classic: return "Classic"
        case .midnight: return "Midnight"
        case .regal: return "Regal"
        case .peacock: return "Peacock"
        case .rose: return "Rose"
        case .moss: return "Moss"
        case .snow: return "Snow"
        case .lavender: return "Lavender"
        case .ember: return "Ember"
        case .honey: return "Honey"
        case .cocoa: return "Cocoa"
        case .ocean: return "Ocean"
        case .mint: return "Mint"
        case .slate: return "Slate"
        case .cherry: return "Cherry"
        case .tangerine: return "Tangerine"
        case .lemon: return "Lemon"
        case .lime: return "Lime"
        case .forest: return "Forest"
        case .sky: return "Sky"
        case .navy: return "Navy"
        case .royal: return "Royal"
        case .plum: return "Plum"
        case .bubblegum: return "Bubblegum"
        case .coral: return "Coral"
        case .sand: return "Sand"
        case .charcoal: return "Charcoal"
        case .copper: return "Copper"
        case .olive: return "Olive"
        case .ghost: return "Ghost"
        }
    }
    var body: RGB {
        switch self {
        case .classic: return RGB(0.878, 0.604, 0.333)
        case .midnight: return RGB(0.20, 0.19, 0.22)
        case .regal: return RGB(0.16, 0.14, 0.16)
        case .peacock: return RGB(0.16, 0.55, 0.62)
        case .rose: return RGB(0.94, 0.58, 0.68)
        case .moss: return RGB(0.48, 0.62, 0.32)
        case .snow: return RGB(0.95, 0.93, 0.88)
        case .lavender: return RGB(0.72, 0.62, 0.86)
        case .ember: return RGB(0.86, 0.32, 0.22)
        case .honey: return RGB(0.95, 0.76, 0.28)
        case .cocoa: return RGB(0.45, 0.29, 0.20)
        case .ocean: return RGB(0.26, 0.42, 0.78)
        case .mint: return RGB(0.60, 0.86, 0.72)
        case .slate: return RGB(0.50, 0.55, 0.60)
        case .cherry: return RGB(0.62, 0.10, 0.16)
        case .tangerine: return RGB(0.98, 0.52, 0.12)
        case .lemon: return RGB(0.99, 0.92, 0.30)
        case .lime: return RGB(0.68, 0.88, 0.22)
        case .forest: return RGB(0.16, 0.38, 0.24)
        case .sky: return RGB(0.62, 0.82, 0.96)
        case .navy: return RGB(0.12, 0.18, 0.40)
        case .royal: return RGB(0.42, 0.20, 0.72)
        case .plum: return RGB(0.48, 0.16, 0.38)
        case .bubblegum: return RGB(0.98, 0.42, 0.72)
        case .coral: return RGB(0.98, 0.50, 0.42)
        case .sand: return RGB(0.86, 0.78, 0.62)
        case .charcoal: return RGB(0.30, 0.30, 0.32)
        case .copper: return RGB(0.72, 0.42, 0.22)
        case .olive: return RGB(0.56, 0.56, 0.28)
        case .ghost: return RGB(0.90, 0.90, 0.96)
        }
    }
    var legs: RGB {
        switch self {
        case .classic: return RGB(0.788, 0.518, 0.278)
        case .midnight: return RGB(0.17, 0.16, 0.19)
        case .regal: return RGB(0.14, 0.12, 0.14)
        case .peacock: return RGB(0.12, 0.42, 0.50)
        case .rose: return RGB(0.86, 0.48, 0.58)
        case .moss: return RGB(0.40, 0.52, 0.26)
        case .snow: return RGB(0.86, 0.83, 0.78)
        case .lavender: return RGB(0.62, 0.52, 0.78)
        case .ember: return RGB(0.72, 0.26, 0.18)
        case .honey: return RGB(0.86, 0.64, 0.22)
        case .cocoa: return RGB(0.38, 0.24, 0.16)
        case .ocean: return RGB(0.20, 0.34, 0.66)
        case .mint: return RGB(0.48, 0.74, 0.60)
        case .slate: return RGB(0.42, 0.46, 0.52)
        case .cherry: return RGB(0.48, 0.08, 0.12)
        case .tangerine: return RGB(0.86, 0.40, 0.08)
        case .lemon: return RGB(0.90, 0.80, 0.20)
        case .lime: return RGB(0.54, 0.74, 0.16)
        case .forest: return RGB(0.12, 0.30, 0.18)
        case .sky: return RGB(0.50, 0.70, 0.88)
        case .navy: return RGB(0.09, 0.13, 0.30)
        case .royal: return RGB(0.34, 0.15, 0.60)
        case .plum: return RGB(0.38, 0.12, 0.30)
        case .bubblegum: return RGB(0.88, 0.32, 0.62)
        case .coral: return RGB(0.88, 0.40, 0.34)
        case .sand: return RGB(0.76, 0.66, 0.50)
        case .charcoal: return RGB(0.22, 0.22, 0.24)
        case .copper: return RGB(0.58, 0.32, 0.16)
        case .olive: return RGB(0.44, 0.44, 0.20)
        case .ghost: return RGB(0.80, 0.80, 0.90)
        }
    }
}

/// Colour used for the abdomen pattern, bands, socks and the like.
enum Accent: String, Codable, CaseIterable {
    case cream, white, black, red, blue, gold, pink, green, orange, purple
    case teal, navy, lime, brown, grey, magenta, lilac, peach, turquoise, maroon
    var label: String {
        switch self {
        case .cream: return "Cream"
        case .white: return "White"
        case .black: return "Black"
        case .red: return "Red"
        case .blue: return "Blue"
        case .gold: return "Gold"
        case .pink: return "Pink"
        case .green: return "Green"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .teal: return "Teal"
        case .navy: return "Navy"
        case .lime: return "Lime"
        case .brown: return "Brown"
        case .grey: return "Grey"
        case .magenta: return "Magenta"
        case .lilac: return "Lilac"
        case .peach: return "Peach"
        case .turquoise: return "Turquoise"
        case .maroon: return "Maroon"
        }
    }
    var rgb: RGB {
        switch self {
        case .cream: return RGB(0.97, 0.91, 0.78)
        case .white: return RGB(1, 1, 1)
        case .black: return RGB(0.14, 0.11, 0.10)
        case .red: return RGB(0.88, 0.26, 0.24)
        case .blue: return RGB(0.30, 0.52, 0.90)
        case .gold: return RGB(0.98, 0.80, 0.30)
        case .pink: return RGB(0.98, 0.56, 0.72)
        case .green: return RGB(0.36, 0.74, 0.42)
        case .orange: return RGB(0.98, 0.58, 0.22)
        case .purple: return RGB(0.60, 0.40, 0.84)
        case .teal: return RGB(0.16, 0.62, 0.62)
        case .navy: return RGB(0.14, 0.20, 0.44)
        case .lime: return RGB(0.74, 0.92, 0.30)
        case .brown: return RGB(0.48, 0.32, 0.20)
        case .grey: return RGB(0.60, 0.62, 0.66)
        case .magenta: return RGB(0.90, 0.20, 0.62)
        case .lilac: return RGB(0.80, 0.70, 0.94)
        case .peach: return RGB(1.0, 0.78, 0.62)
        case .turquoise: return RGB(0.30, 0.86, 0.84)
        case .maroon: return RGB(0.50, 0.12, 0.20)
        }
    }
}

struct RGB: Equatable, Hashable, Codable {
    var r: CGFloat, g: CGFloat, b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }
    var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
    func alpha(_ a: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
    func mix(_ o: RGB, _ t: CGFloat) -> RGB { RGB(lerp(r, o.r, t), lerp(g, o.g, t), lerp(b, o.b, t)) }
    func lighter(_ t: CGFloat) -> RGB { mix(RGB(1, 1, 1), t) }
    func darker(_ t: CGFloat) -> RGB { mix(RGB(0.08, 0.04, 0.02), t) }
    var luma: CGFloat { 0.3 * r + 0.59 * g + 0.11 * b }

    /// A colour from a hue (0..1 round the wheel), for rainbows and the like.
    static func hue(_ h: CGFloat, sat: CGFloat = 1, val: CGFloat = 1) -> RGB {
        let hh = (h - floor(h)) * 6
        let i = Int(hh), f = hh - CGFloat(i)
        let p = val * (1 - sat), q = val * (1 - sat * f), t = val * (1 - sat * (1 - f))
        switch i % 6 {
        case 0: return RGB(val, t, p)
        case 1: return RGB(q, val, p)
        case 2: return RGB(p, val, t)
        case 3: return RGB(p, q, val)
        case 4: return RGB(t, p, val)
        default: return RGB(val, p, q)
        }
    }

    var ns: NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }
    init(_ c: NSColor) {
        let s = c.usingColorSpace(.sRGB) ?? c
        r = s.redComponent; g = s.greenComponent; b = s.blueComponent
    }
}

/// Which way the studio's coat is painted: a flat preset, a preset
/// gradient, a living (moving) coat, or colours of your own.
enum SkinKind: String, Codable, CaseIterable {
    case coat, gradient, living, custom, customGradient
}

/// Which way a gradient runs across the body.
enum GradientDirection: String, Codable, CaseIterable {
    case along, down, diagonal, radial
    var label: String {
        switch self {
        case .along: return "Nose to tail"
        case .down: return "Top to bottom"
        case .diagonal: return "Diagonal"
        case .radial: return "From the middle"
        }
    }
}

/// Preset two- and three-colour coats.
enum GradientCoat: String, Codable, CaseIterable {
    case sunset, dusk, meadow, deepSea, cottonCandy, emberGlow, mintChip, lemonade
    case forest, twilight, peach, sky, blueberry, autumn, neon, ash
    var label: String {
        switch self {
        case .sunset: return "Sunset"
        case .dusk: return "Dusk"
        case .meadow: return "Meadow"
        case .deepSea: return "Deep Sea"
        case .cottonCandy: return "Cotton Candy"
        case .emberGlow: return "Ember Glow"
        case .mintChip: return "Mint Chip"
        case .lemonade: return "Lemonade"
        case .forest: return "Forest"
        case .twilight: return "Twilight"
        case .peach: return "Peach"
        case .sky: return "Sky"
        case .blueberry: return "Blueberry"
        case .autumn: return "Autumn"
        case .neon: return "Neon"
        case .ash: return "Ash"
        }
    }
    var stops: [RGB] {
        switch self {
        case .sunset: return [RGB(0.98, 0.62, 0.22), RGB(0.94, 0.38, 0.48), RGB(0.46, 0.24, 0.62)]
        case .dusk: return [RGB(0.14, 0.18, 0.42), RGB(0.62, 0.24, 0.56)]
        case .meadow: return [RGB(0.30, 0.62, 0.30), RGB(0.86, 0.88, 0.36)]
        case .deepSea: return [RGB(0.10, 0.16, 0.36), RGB(0.16, 0.56, 0.62)]
        case .cottonCandy: return [RGB(0.98, 0.66, 0.84), RGB(0.62, 0.80, 0.98)]
        case .emberGlow: return [RGB(0.34, 0.08, 0.06), RGB(0.98, 0.50, 0.16)]
        case .mintChip: return [RGB(0.62, 0.90, 0.76), RGB(0.42, 0.26, 0.18)]
        case .lemonade: return [RGB(0.99, 0.92, 0.40), RGB(0.98, 0.56, 0.68)]
        case .forest: return [RGB(0.10, 0.28, 0.16), RGB(0.56, 0.78, 0.36)]
        case .twilight: return [RGB(0.42, 0.20, 0.66), RGB(0.24, 0.42, 0.86)]
        case .peach: return [RGB(0.99, 0.70, 0.50), RGB(0.99, 0.92, 0.80)]
        case .sky: return [RGB(0.30, 0.60, 0.94), RGB(0.90, 0.96, 1.0)]
        case .blueberry: return [RGB(0.24, 0.34, 0.80), RGB(0.50, 0.24, 0.62)]
        case .autumn: return [RGB(0.92, 0.50, 0.14), RGB(0.52, 0.24, 0.10), RGB(0.96, 0.78, 0.26)]
        case .neon: return [RGB(0.96, 0.16, 0.72), RGB(0.16, 0.92, 0.96)]
        case .ash: return [RGB(0.12, 0.11, 0.12), RGB(0.62, 0.62, 0.64)]
        }
    }
    var direction: GradientDirection {
        switch self {
        case .sunset, .sky, .peach, .emberGlow, .forest, .ash: return .down
        case .cottonCandy, .neon, .twilight, .blueberry, .lemonade: return .diagonal
        case .dusk, .meadow, .deepSea, .autumn: return .along
        case .mintChip: return .radial
        }
    }
}

/// Coats that move: colours that shift, drift, pulse or match the world.
enum LivingCoat: String, Codable, CaseIterable {
    case rainbow, lava, camo, galaxy, ocean, aurora, disco, fire, frost, toxic, pearl, candy, storm, chrome
    var label: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .lava: return "Hot Lava"
        case .camo: return "Camouflage"
        case .galaxy: return "Galaxy"
        case .ocean: return "Ocean"
        case .aurora: return "Aurora"
        case .disco: return "Disco"
        case .fire: return "Fire"
        case .frost: return "Frost"
        case .toxic: return "Toxic"
        case .pearl: return "Pearl"
        case .candy: return "Candy Cane"
        case .storm: return "Thunderstorm"
        case .chrome: return "Chrome"
        }
    }
    var blurb: String {
        switch self {
        case .rainbow: return "Every colour, sliding along it."
        case .lava: return "Glowing cracks between shifting crust."
        case .camo: return "Takes on the colour of whatever is behind it."
        case .galaxy: return "Deep space, with twinkling stars."
        case .ocean: return "Waves rolling down its back."
        case .aurora: return "Northern lights drifting over it."
        case .disco: return "Cycles slowly through every hue."
        case .fire: return "Flickering flame."
        case .frost: return "Pale ice, glittering."
        case .toxic: return "Bright green ooze, pulsing."
        case .pearl: return "Soft shimmering pastels."
        case .candy: return "Stripes turning like a barber's pole."
        case .storm: return "Grey cloud, with lightning now and then."
        case .chrome: return "Polished metal with a sweeping shine."
        }
    }
}

/// Your own flat colours.
struct CustomColours: Codable, Hashable {
    var body = RGB(0.878, 0.604, 0.333)
    var legs = RGB(0.788, 0.518, 0.278)
}

/// Your own gradient: two or three colours, a direction, and whether it
/// shimmers (drifts slowly back and forth).
struct CustomGradient: Codable, Hashable {
    var a = RGB(0.98, 0.62, 0.22)
    var b = RGB(0.46, 0.24, 0.62)
    var c = RGB(0.30, 0.52, 0.90)
    var threeColours = false
    var direction: GradientDirection = .down
    var shimmer = false
    var stops: [RGB] { threeColours ? [a, b, c] : [a, b] }
}

struct SpiderLook: Codable, Hashable {
    var body: BodyShape = .classic
    var eyes: EyeStyle = .classic
    var brows: BrowStyle = .none
    var fangs: FangStyle = .none
    var legs: LegStyle = .classic
    var pattern: Pattern = .plain
    var skin: SkinKind = .coat
    var coat: Coat = .classic
    var gradient: GradientCoat = .sunset
    var living: LivingCoat = .rainbow
    var custom = CustomColours()
    var customGradient = CustomGradient()
    /// Measurements for the hand-shaped body, eyes and legs; used when
    /// that part is set to `.custom`.
    var bodyTune = BodyTune()
    var eyeTune = EyeTune()
    var legTune = LegTune()
    var accent: Accent = .cream
    /// A colour of your own for the markings, instead of a preset.
    var customAccent: RGB? = nil
    var hat: Hat = .none
    var accessory: Accessory = .none
    /// 0 sleek .. 2 very fuzzy.
    var fuzz: Int = 1
    /// Whether the face is drawn in front of the near-side legs (the leg that
    /// reaches ahead of the face crosses it) or behind them.
    var faceOverLegs = true

    init() {}

    /// The colour the markings are painted in.
    var accentRGB: RGB { customAccent ?? accent.rgb }
    /// Whether the coat changes from frame to frame, so it has to be
    /// redrawn even while it is standing still.
    var isAnimated: Bool {
        skin == .living || (skin == .customGradient && customGradient.shimmer)
    }
    var isCamouflaged: Bool { skin == .living && living == .camo }

    /// The measurements of each part as it is: the preset's, or the hand
    /// tuning for a custom one.
    var bodyMetrics: (arx: CGFloat, ary: CGFloat, head: CGFloat) {
        body == .custom ? (bodyTune.width, bodyTune.height, bodyTune.head) : body.metrics
    }
    var legMetrics: (width: CGFloat, reach: CGFloat, knee: CGFloat) {
        legs == .custom ? (legTune.width, legTune.reach, legTune.knee) : legs.metrics
    }
    var eyeSize: CGFloat { eyes == .custom ? eyeTune.size : eyes.sizeMul }
    var eyeSquash: CGFloat { eyes == .custom ? eyeTune.height : eyes.squash }
    var eyeSpread: CGFloat { eyes == .custom ? eyeTune.spread : 1 }
    var eyeLid: CGFloat { eyes == .custom ? eyeTune.lids : eyes.lid }

    // Older saved looks lack the newer fields.
    private enum CodingKeys: String, CodingKey {
        case body, eyes, brows, fangs, legs, pattern, skin, coat, gradient, living, custom, customGradient
        case bodyTune, eyeTune, legTune
        case accent, customAccent, hat, accessory, fuzz, faceOverLegs
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body = (try? c.decodeIfPresent(BodyShape.self, forKey: .body)) ?? .classic
        eyes = (try? c.decodeIfPresent(EyeStyle.self, forKey: .eyes)) ?? .classic
        brows = (try? c.decodeIfPresent(BrowStyle.self, forKey: .brows)) ?? .none
        fangs = (try? c.decodeIfPresent(FangStyle.self, forKey: .fangs)) ?? .none
        legs = (try? c.decodeIfPresent(LegStyle.self, forKey: .legs)) ?? .classic
        pattern = (try? c.decodeIfPresent(Pattern.self, forKey: .pattern)) ?? .plain
        skin = (try? c.decodeIfPresent(SkinKind.self, forKey: .skin)) ?? .coat
        coat = (try? c.decodeIfPresent(Coat.self, forKey: .coat)) ?? .classic
        gradient = (try? c.decodeIfPresent(GradientCoat.self, forKey: .gradient)) ?? .sunset
        living = (try? c.decodeIfPresent(LivingCoat.self, forKey: .living)) ?? .rainbow
        custom = (try? c.decodeIfPresent(CustomColours.self, forKey: .custom)) ?? CustomColours()
        customGradient = (try? c.decodeIfPresent(CustomGradient.self, forKey: .customGradient)) ?? CustomGradient()
        bodyTune = (try? c.decodeIfPresent(BodyTune.self, forKey: .bodyTune)) ?? BodyTune()
        eyeTune = (try? c.decodeIfPresent(EyeTune.self, forKey: .eyeTune)) ?? EyeTune()
        legTune = (try? c.decodeIfPresent(LegTune.self, forKey: .legTune)) ?? LegTune()
        accent = (try? c.decodeIfPresent(Accent.self, forKey: .accent)) ?? .cream
        customAccent = try? c.decodeIfPresent(RGB.self, forKey: .customAccent)
        hat = (try? c.decodeIfPresent(Hat.self, forKey: .hat)) ?? .none
        accessory = (try? c.decodeIfPresent(Accessory.self, forKey: .accessory)) ?? .none
        fuzz = (try? c.decodeIfPresent(Int.self, forKey: .fuzz)) ?? 1
        faceOverLegs = (try? c.decodeIfPresent(Bool.self, forKey: .faceOverLegs)) ?? true
    }

    static func random() -> SpiderLook {
        var l = SpiderLook()
        l.body = BodyShape.allCases.filter { $0 != .custom }.randomElement()!
        l.eyes = EyeStyle.allCases.filter { $0 != .custom }.randomElement()!
        l.brows = chance(0.5) ? .none : BrowStyle.allCases.randomElement()!
        l.fangs = chance(0.5) ? .none : FangStyle.allCases.randomElement()!
        l.legs = LegStyle.allCases.filter { $0 != .custom }.randomElement()!
        l.pattern = Pattern.allCases.randomElement()!
        let roll = CGFloat.random(in: 0..<1)
        if roll < 0.5 {
            l.skin = .coat
            l.coat = Coat.allCases.randomElement()!
        } else if roll < 0.72 {
            l.skin = .gradient
            l.gradient = GradientCoat.allCases.randomElement()!
        } else if roll < 0.88 {
            l.skin = .living
            l.living = LivingCoat.allCases.randomElement()!
        } else {
            l.skin = .custom
            let h = CGFloat.random(in: 0..<1)
            l.custom.body = RGB.hue(h, sat: randRange(0.3, 0.8), val: randRange(0.55, 0.95))
            l.custom.legs = l.custom.body.darker(0.2)
        }
        l.accent = Accent.allCases.randomElement()!
        l.customAccent = nil
        l.hat = chance(0.45) ? .none : Hat.allCases.randomElement()!
        l.accessory = chance(0.5) ? .none : Accessory.allCases.randomElement()!
        l.fuzz = Int.random(in: 0...2)
        l.faceOverLegs = true
        return l
    }
}

// MARK: - Personality
//
// Sliders, 0..1, that weight the decisions it makes. Nothing here is a switch:
// a shy spider still waves sometimes, a lazy one still jumps.

struct Personality: Codable, Equatable {
    var energy: CGFloat = 0.5       // how often it does anything at all
    var curiosity: CGFloat = 0.5    // interest in the pointer
    var bravery: CGFloat = 0.5      // how hard it is to startle
    var playfulness: CGFloat = 0.5  // dances, rolls, spins, hops
    var affection: CGFloat = 0.5    // waves, glances at you, hearts
    var laziness: CGFloat = 0.3     // rests and naps

    /// Liveliness multiplier the decision clock runs at.
    var liveliness: CGFloat { lerp(0.45, 2.4, energy) }

    struct Preset {
        let name: String
        let p: Personality
    }
    static let presets: [Preset] = [
        Preset(name: "Friendly", p: Personality(energy: 0.55, curiosity: 0.7, bravery: 0.6, playfulness: 0.55, affection: 0.85, laziness: 0.25)),
        Preset(name: "Shy", p: Personality(energy: 0.4, curiosity: 0.35, bravery: 0.15, playfulness: 0.3, affection: 0.4, laziness: 0.35)),
        Preset(name: "Hyper", p: Personality(energy: 0.95, curiosity: 0.7, bravery: 0.7, playfulness: 0.9, affection: 0.6, laziness: 0.05)),
        Preset(name: "Lazy", p: Personality(energy: 0.2, curiosity: 0.3, bravery: 0.6, playfulness: 0.2, affection: 0.5, laziness: 0.9)),
        Preset(name: "Curious", p: Personality(energy: 0.6, curiosity: 0.95, bravery: 0.55, playfulness: 0.45, affection: 0.5, laziness: 0.2)),
        Preset(name: "Show-off", p: Personality(energy: 0.7, curiosity: 0.5, bravery: 0.85, playfulness: 0.95, affection: 0.7, laziness: 0.1)),
        Preset(name: "Chill", p: Personality(energy: 0.35, curiosity: 0.45, bravery: 0.75, playfulness: 0.35, affection: 0.55, laziness: 0.5)),
        Preset(name: "Grumpy", p: Personality(energy: 0.45, curiosity: 0.3, bravery: 0.9, playfulness: 0.1, affection: 0.15, laziness: 0.45)),
    ]

    static func random() -> Personality {
        Personality(energy: randRange(0.15, 0.95), curiosity: randRange(0.1, 1), bravery: randRange(0.1, 1),
                    playfulness: randRange(0.1, 1), affection: randRange(0.1, 1), laziness: randRange(0, 0.85))
    }
}

// MARK: - Gait

enum GaitPreference: String, Codable, CaseIterable {
    case mixed, march, bouncy, tiptoe, lumber, scurry
    var label: String {
        switch self {
        case .mixed: return "Mixed"
        case .march: return "Steady"
        case .bouncy: return "Bouncy"
        case .tiptoe: return "Tiptoe"
        case .lumber: return "Lumbering"
        case .scurry: return "Scurrying"
        }
    }
}

struct Gait: Codable, Equatable {
    var pace: CGFloat = 0.5        // walking speed
    var stride: CGFloat = 0.5      // step length
    var bounce: CGFloat = 0.5      // how much the body bobs
    var stance: CGFloat = 0.5      // 0 low and flat .. 1 up on its toes
    var style: GaitPreference = .mixed

    var speedMul: CGFloat { lerp(0.55, 1.7, pace) }
    var strideMul: CGFloat { lerp(0.72, 1.3, stride) }
    var bobMul: CGFloat { lerp(0.3, 1.9, bounce) }
    /// Resting lift off the ledge, in body units.
    var liftOffset: CGFloat { lerp(-2.5, 3.5, stance) }

    static func random() -> Gait {
        Gait(pace: randRange(0.1, 1), stride: randRange(0.1, 1), bounce: randRange(0.1, 1),
             stance: randRange(0.1, 1), style: GaitPreference.allCases.randomElement()!)
    }
}

/// How often it gets up to each thing it does on its own, one dial per
/// habit. Each is 0…1: at 0 it never does that; at ½ it does it as often
/// as it always has; at 1 it does it every chance it gets. They scale the
/// weights in its weighted draw, on top of whatever its personality says.
struct Habits: Codable, Equatable {
    // Getting about
    var wander: CGFloat = 0.5
    var leap: CGFloat = 0.5
    var rappel: CGFloat = 0.5
    var swing: CGFloat = 0.5
    var hammock: CGFloat = 0.5
    var nap: CGFloat = 0.5
    var sleep: CGFloat = 0.5
    // Antics
    var drum: CGFloat = 0.5
    var dance: CGFloat = 0.5
    var roll: CGFloat = 0.5
    var spin: CGFloat = 0.5
    var pushup: CGFloat = 0.5
    var stretch: CGFloat = 0.5
    var wiggle: CGFloat = 0.5
    var armsUp: CGFloat = 0.5
    // Quiet moments
    var look: CGFloat = 0.5
    var rest: CGFloat = 0.5
    var groom: CGFloat = 0.5
    var fidget: CGFloat = 0.5
    var scratch: CGFloat = 0.5
    var peer: CGFloat = 0.5
    var muse: CGFloat = 0.5
    // With you
    var approach: CGFloat = 0.5
    var curious: CGFloat = 0.5
    var stare: CGFloat = 0.5
    var glance: CGFloat = 0.5
    var greet: CGFloat = 0.5
    var wave: CGFloat = 0.5
    var peekaboo: CGFloat = 0.5

    /// The multiplier a dial setting puts on a weight: nothing at all at
    /// 0, one at ½, and so much at 1 that the draw is as good as decided
    /// whenever the thing is possible.
    static func weight(_ v: CGFloat) -> CGFloat {
        if v >= 0.995 { return 100_000 }
        if v <= 0.5 { return max(0, v * 2) }
        return pow(400, (v - 0.5) * 2)
    }

    /// Every dial, grouped for the studio.
    static let groups: [(String, [(String, WritableKeyPath<Habits, CGFloat>)])] = [
        ("Getting about", [
            ("Wandering", \.wander), ("Leaping between windows", \.leap),
            ("Dropping on a thread", \.rappel), ("Swinging on a line", \.swing),
            ("Building a hammock", \.hammock), ("Napping in the hammock", \.nap),
            ("Nodding off", \.sleep),
        ]),
        ("Antics", [
            ("Drumming", \.drum), ("Dancing", \.dance), ("Rolling over", \.roll),
            ("Spinning round", \.spin), ("Push-ups", \.pushup), ("Stretching", \.stretch),
            ("Wiggling", \.wiggle), ("Arms up", \.armsUp),
        ]),
        ("Quiet moments", [
            ("Looking about", \.look), ("Resting", \.rest), ("Grooming", \.groom),
            ("Fidgeting", \.fidget), ("Scratching", \.scratch), ("Peering over the edge", \.peer),
            ("Thinking out loud", \.muse),
        ]),
        ("With you", [
            ("Coming to see the pointer", \.approach), ("Craning at the pointer", \.curious),
            ("Staring at you", \.stare), ("Glancing your way", \.glance),
            ("Greeting you", \.greet), ("Waving", \.wave), ("Peek-a-boo", \.peekaboo),
        ]),
    ]
}

// MARK: - The whole design

/// Sets of things it can think in a thought bubble.
enum ThoughtPack: String, Codable, CaseIterable {
    case chitchat, encouragement, spiderFacts, bibleVerses

    var label: String {
        switch self {
        case .chitchat: return "Chit-chat"
        case .encouragement: return "Encouragement"
        case .spiderFacts: return "Spider facts"
        case .bibleVerses: return "Bible verses"
        }
    }

    var phrases: [String] {
        switch self {
        case .chitchat:
            return ["hi!", "hello there", "boo!", "hmm…", "ooh", "what's that?", "nice window", "la la la",
                    "I like it here", "hey you", "psst", "yum?", "brb", "tap tap", "cosy", "wheee",
                    "up we go", "ta-da!", "just chilling", "you again!", "*wiggles*", "snack o'clock?"]
        case .encouragement:
            return ["you've got this", "drink some water", "take a little break", "nice work", "keep going",
                    "stretch your legs", "one thing at a time", "you're doing great", "breathe", "almost there",
                    "proud of you", "look out the window", "be kind to yourself", "good job today", "sit up straight",
                    "you can do hard things", "have a snack", "rest your eyes a moment"]
        case .spiderFacts:
            return ["jumping spiders can see in colour", "I have eight eyes", "I don't spin webs to catch things",
                    "I can jump 50 times my length", "my silk is a safety line", "I hunt by sight",
                    "I do a little dance to say hi", "spiders aren't insects", "I sleep in a silk hammock",
                    "I can see the moon", "my fangs fold away", "I molt as I grow", "I breathe through book lungs",
                    "I drum to talk", "there are 6,000 kinds of me"]
        case .bibleVerses:
            return ["\u{201C}The LORD is my shepherd; I shall not want.\u{201D} \u{2014} Psalm 23:1",
                    "\u{201C}Be still, and know that I am God.\u{201D} \u{2014} Psalm 46:10",
                    "\u{201C}I can do all things through Christ which strengtheneth me.\u{201D} \u{2014} Philippians 4:13",
                    "\u{201C}Love is patient, love is kind.\u{201D} \u{2014} 1 Corinthians 13:4",
                    "\u{201C}Rejoice evermore.\u{201D} \u{2014} 1 Thessalonians 5:16",
                    "\u{201C}Be careful for nothing; but in every thing by prayer\u{2026} let your requests be made known unto God.\u{201D} \u{2014} Philippians 4:6",
                    "\u{201C}Fear thou not; for I am with thee.\u{201D} \u{2014} Isaiah 41:10",
                    "\u{201C}The joy of the LORD is your strength.\u{201D} \u{2014} Nehemiah 8:10",
                    "\u{201C}Trust in the LORD with all thine heart.\u{201D} \u{2014} Proverbs 3:5",
                    "\u{201C}This is the day which the LORD hath made; we will rejoice and be glad in it.\u{201D} \u{2014} Psalm 118:24",
                    "\u{201C}In every thing give thanks.\u{201D} \u{2014} 1 Thessalonians 5:18",
                    "\u{201C}Let all your things be done with charity.\u{201D} \u{2014} 1 Corinthians 16:14",
                    "\u{201C}Be strong and of a good courage.\u{201D} \u{2014} Joshua 1:9",
                    "\u{201C}Casting all your care upon him; for he careth for you.\u{201D} \u{2014} 1 Peter 5:7",
                    "\u{201C}All things work together for good to them that love God.\u{201D} \u{2014} Romans 8:28",
                    "\u{201C}Thy word is a lamp unto my feet, and a light unto my path.\u{201D} \u{2014} Psalm 119:105",
                    "\u{201C}Come unto me, all ye that labour and are heavy laden, and I will give you rest.\u{201D} \u{2014} Matthew 11:28",
                    "\u{201C}The LORD bless thee, and keep thee.\u{201D} \u{2014} Numbers 6:24"]
        }
    }
}

struct SpiderDesign: Codable, Equatable {
    var name: String = "Spider"
    var look = SpiderLook()
    var personality = Personality()
    var gait = Gait()
    var habits = Habits()
    /// Which packs of things it thinks, and any of your own.
    var packs: [ThoughtPack] = [.chitchat]
    var customPhrases: [String] = []

    init(name: String = "Spider", look: SpiderLook = SpiderLook(), personality: Personality = Personality(),
         gait: Gait = Gait(), habits: Habits = Habits(), packs: [ThoughtPack] = [.chitchat], customPhrases: [String] = []) {
        self.name = name
        self.look = look
        self.personality = personality
        self.gait = gait
        self.habits = habits
        self.packs = packs
        self.customPhrases = customPhrases
    }

    // Older saved designs have no thought or habit fields.
    private enum CodingKeys: String, CodingKey { case name, look, personality, gait, habits, packs, customPhrases }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Spider"
        look = try c.decodeIfPresent(SpiderLook.self, forKey: .look) ?? SpiderLook()
        personality = try c.decodeIfPresent(Personality.self, forKey: .personality) ?? Personality()
        gait = try c.decodeIfPresent(Gait.self, forKey: .gait) ?? Gait()
        habits = try c.decodeIfPresent(Habits.self, forKey: .habits) ?? Habits()
        packs = try c.decodeIfPresent([ThoughtPack].self, forKey: .packs) ?? [.chitchat]
        customPhrases = try c.decodeIfPresent([String].self, forKey: .customPhrases) ?? []
    }

    /// Everything it might say, from the packs it has and your own lines.
    var allPhrases: [String] {
        packs.flatMap { $0.phrases } + customPhrases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static let key = "design"

    static func load() -> SpiderDesign {
        guard let data = UserDefaults.standard.data(forKey: key),
              let d = try? JSONDecoder().decode(SpiderDesign.self, from: data) else { return SpiderDesign() }
        return d
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: SpiderDesign.key)
        }
    }

    static let randomNames = ["Pip", "Mochi", "Biscuit", "Juniper", "Widget", "Clover", "Ziggy", "Pebble",
                              "Noodle", "Fig", "Pixel", "Maple", "Tofu", "Sprocket", "Peanut", "Dot",
                              "Bramble", "Waffle", "Comet", "Olive", "Ginger", "Bean", "Nimbus", "Poppy"]

    static func random() -> SpiderDesign {
        SpiderDesign(name: randomNames.randomElement()!, look: .random(), personality: .random(), gait: .random())
    }
}
