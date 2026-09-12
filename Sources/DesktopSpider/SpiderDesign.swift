import AppKit
import CoreGraphics

// MARK: - Appearance
//
// Everything the studio can change about how the spider looks. Each part is an
// enum so the options can be listed, thumbnailed and stored by name. The
// renderer reads these every frame; nothing here changes the rig's topology,
// so every option works with every animation.

enum BodyShape: String, Codable, CaseIterable {
    case classic, round, plump, slim, peanut, chonk, tall
    var label: String {
        switch self {
        case .classic: return "Classic"
        case .round: return "Round"
        case .plump: return "Plump"
        case .slim: return "Slim"
        case .peanut: return "Peanut"
        case .chonk: return "Chonk"
        case .tall: return "Tall"
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
        }
    }
}

enum EyeStyle: String, Codable, CaseIterable {
    case classic, huge, beady, sleepy, wide, sparkly, oval, cross
    var label: String {
        switch self {
        case .classic: return "Classic"
        case .huge: return "Huge"
        case .beady: return "Beady"
        case .sleepy: return "Sleepy"
        case .wide: return "Wide"
        case .sparkly: return "Sparkly"
        case .oval: return "Oval"
        case .cross: return "Cross-eyed"
        }
    }
    var sizeMul: CGFloat {
        switch self {
        case .huge: return 1.22
        case .beady: return 0.7
        case .wide: return 1.08
        default: return 1
        }
    }
    /// Resting eyelid, 0..1.
    var lid: CGFloat { self == .sleepy ? 0.42 : 0 }
    /// Vertical squash for oval eyes.
    var squash: CGFloat { self == .oval ? 1.25 : 1 }
}

enum BrowStyle: String, Codable, CaseIterable {
    case none, soft, arched, stern, worried, unibrow, thick
    var label: String {
        switch self {
        case .none: return "None"
        case .soft: return "Soft"
        case .arched: return "Arched"
        case .stern: return "Stern"
        case .worried: return "Worried"
        case .unibrow: return "Unibrow"
        case .thick: return "Thick"
        }
    }
}

enum FangStyle: String, Codable, CaseIterable {
    case none, tiny, big, tusks, emerald, smile
    var label: String {
        switch self {
        case .none: return "None"
        case .tiny: return "Tiny"
        case .big: return "Big"
        case .tusks: return "Tusks"
        case .emerald: return "Emerald"
        case .smile: return "Smile"
        }
    }
}

enum LegStyle: String, Codable, CaseIterable {
    case classic, slender, chunky, stubby, long, fuzzy, banded, socks
    var label: String {
        switch self {
        case .classic: return "Classic"
        case .slender: return "Slender"
        case .chunky: return "Chunky"
        case .stubby: return "Stubby"
        case .long: return "Long"
        case .fuzzy: return "Fuzzy"
        case .banded: return "Banded"
        case .socks: return "Socks"
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
        }
    }
}

enum Pattern: String, Codable, CaseIterable {
    case plain, stripe, spots, chevron, heart, star, saddle, bands, diamond
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
        }
    }
}

enum Hat: String, Codable, CaseIterable {
    case none, topHat, partyHat, crown, beanie, flower, bow, cap, halo, wizard, propeller
    case cowboy, chef, bucket, viking, tiara, pirate, mushroom
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
        }
    }
}

enum Accessory: String, Codable, CaseIterable {
    case none, glasses, monocle, bowTie, scarf, headphones, bandana, backpack, sunglasses
    case cape, satchel, collar, necktie, wings, lei
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
        }
    }
}

/// Body colourways. Each is a base body tone and a leg tone; the renderer
/// derives highlights, shadows and the outline from them.
enum Coat: String, Codable, CaseIterable {
    case classic, midnight, regal, peacock, rose, moss, snow, lavender, ember, honey, cocoa, ocean, mint, slate
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
        }
    }
}

/// Colour used for the abdomen pattern, bands, socks and the like.
enum Accent: String, Codable, CaseIterable {
    case cream, white, black, red, blue, gold, pink, green, orange, purple
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
        }
    }
}

struct RGB: Equatable {
    var r: CGFloat, g: CGFloat, b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }
    var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
    func alpha(_ a: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
    func mix(_ o: RGB, _ t: CGFloat) -> RGB { RGB(lerp(r, o.r, t), lerp(g, o.g, t), lerp(b, o.b, t)) }
    func lighter(_ t: CGFloat) -> RGB { mix(RGB(1, 1, 1), t) }
    func darker(_ t: CGFloat) -> RGB { mix(RGB(0.08, 0.04, 0.02), t) }
    var luma: CGFloat { 0.3 * r + 0.59 * g + 0.11 * b }
}

/// The derived colours the renderer actually paints with.
struct Palette {
    var outline: CGColor
    var outlineFar: CGColor
    var bodyFill: CGColor
    var bodyLight: CGColor
    var headFill: CGColor
    var legFill: CGColor
    var legLight: CGColor
    var legFar: CGColor
    var eyeDark: CGColor
    var accent: CGColor
    var accentRGB: RGB

    init(coat: Coat, accent: Accent) {
        let body = coat.body, legs = coat.legs
        // Dark coats need a rim that is lighter than the body, not darker,
        // or the outline disappears.
        let dark = body.luma < 0.3
        let rim = dark ? body.lighter(0.22) : body.darker(0.66)
        outline = rim.cg
        outlineFar = (dark ? rim.darker(0.25) : rim.darker(0.15)).cg
        bodyFill = body.cg
        bodyLight = body.lighter(dark ? 0.16 : 0.34).cg
        headFill = body.mix(legs, 0.25).lighter(0.06).cg
        legFill = legs.cg
        legLight = legs.lighter(0.18).cg
        legFar = legs.darker(0.24).cg
        eyeDark = (dark ? RGB(0.05, 0.04, 0.05) : body.darker(0.78)).cg
        accentRGB = accent.rgb
        self.accent = accent.rgb.cg
    }
}

struct SpiderLook: Codable, Equatable {
    var body: BodyShape = .classic
    var eyes: EyeStyle = .classic
    var brows: BrowStyle = .none
    var fangs: FangStyle = .none
    var legs: LegStyle = .classic
    var pattern: Pattern = .plain
    var coat: Coat = .classic
    var accent: Accent = .cream
    var hat: Hat = .none
    var accessory: Accessory = .none
    /// 0 sleek .. 2 very fuzzy.
    var fuzz: Int = 1

    static func random() -> SpiderLook {
        var l = SpiderLook()
        l.body = BodyShape.allCases.randomElement()!
        l.eyes = EyeStyle.allCases.randomElement()!
        l.brows = chance(0.5) ? .none : BrowStyle.allCases.randomElement()!
        l.fangs = chance(0.5) ? .none : FangStyle.allCases.randomElement()!
        l.legs = LegStyle.allCases.randomElement()!
        l.pattern = Pattern.allCases.randomElement()!
        l.coat = Coat.allCases.randomElement()!
        l.accent = Accent.allCases.randomElement()!
        l.hat = chance(0.45) ? .none : Hat.allCases.randomElement()!
        l.accessory = chance(0.5) ? .none : Accessory.allCases.randomElement()!
        l.fuzz = Int.random(in: 0...2)
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
    var jumpiness: CGFloat = 0.5   // how keen it is to leap between windows
    var webbiness: CGFloat = 0.5   // how often it drops on a thread

    var speedMul: CGFloat { lerp(0.55, 1.7, pace) }
    var strideMul: CGFloat { lerp(0.72, 1.3, stride) }
    var bobMul: CGFloat { lerp(0.3, 1.9, bounce) }
    /// Resting lift off the ledge, in body units.
    var liftOffset: CGFloat { lerp(-2.5, 3.5, stance) }

    static func random() -> Gait {
        Gait(pace: randRange(0.1, 1), stride: randRange(0.1, 1), bounce: randRange(0.1, 1),
             stance: randRange(0.1, 1), style: GaitPreference.allCases.randomElement()!,
             jumpiness: randRange(0.1, 1), webbiness: randRange(0.1, 1))
    }
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
    /// Which packs of things it thinks, and any of your own.
    var packs: [ThoughtPack] = [.chitchat]
    var customPhrases: [String] = []

    init(name: String = "Spider", look: SpiderLook = SpiderLook(), personality: Personality = Personality(),
         gait: Gait = Gait(), packs: [ThoughtPack] = [.chitchat], customPhrases: [String] = []) {
        self.name = name
        self.look = look
        self.personality = personality
        self.gait = gait
        self.packs = packs
        self.customPhrases = customPhrases
    }

    // Older saved designs have no thought fields.
    private enum CodingKeys: String, CodingKey { case name, look, personality, gait, packs, customPhrases }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Spider"
        look = try c.decodeIfPresent(SpiderLook.self, forKey: .look) ?? SpiderLook()
        personality = try c.decodeIfPresent(Personality.self, forKey: .personality) ?? Personality()
        gait = try c.decodeIfPresent(Gait.self, forKey: .gait) ?? Gait()
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
