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
        case .tundra: return "Tundra"
        case .night: return "Night"
        }
    }
}

/// Things to put in the habitat. Some are furniture it can climb on; some
/// are just scenery.
enum HabitatItemKind: String, Codable, CaseIterable {
    case log, branch, rock, boulder, corkBark, hide, cactus, vine
    case plant, fern, flower, mushrooms, moss, leafPile, waterDish, twigs

    var label: String {
        switch self {
        case .log: return "Log"
        case .branch: return "Branch"
        case .rock: return "Rock"
        case .boulder: return "Boulder"
        case .corkBark: return "Cork Bark"
        case .hide: return "Hollow Log"
        case .cactus: return "Cactus"
        case .vine: return "Hanging Vine"
        case .plant: return "Leafy Plant"
        case .fern: return "Fern"
        case .flower: return "Flowers"
        case .mushrooms: return "Mushrooms"
        case .moss: return "Moss"
        case .leafPile: return "Leaf Litter"
        case .waterDish: return "Water Dish"
        case .twigs: return "Twigs"
        }
    }

    /// Climbable, or just to look at.
    var climbable: Bool {
        switch self {
        case .log, .branch, .rock, .boulder, .corkBark, .hide, .cactus, .vine, .plant, .waterDish: return true
        default: return false
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .log: return CGSize(width: 170, height: 46)
        case .branch: return CGSize(width: 220, height: 120)
        case .rock: return CGSize(width: 70, height: 42)
        case .boulder: return CGSize(width: 130, height: 90)
        case .corkBark: return CGSize(width: 70, height: 200)
        case .hide: return CGSize(width: 120, height: 64)
        case .cactus: return CGSize(width: 44, height: 140)
        case .vine: return CGSize(width: 26, height: 220)
        case .plant: return CGSize(width: 110, height: 130)
        case .fern: return CGSize(width: 120, height: 80)
        case .flower: return CGSize(width: 70, height: 70)
        case .mushrooms: return CGSize(width: 60, height: 40)
        case .moss: return CGSize(width: 110, height: 22)
        case .leafPile: return CGSize(width: 120, height: 26)
        case .waterDish: return CGSize(width: 90, height: 22)
        case .twigs: return CGSize(width: 90, height: 30)
        }
    }

    /// Hangs from the ceiling rather than standing on the floor.
    var hangs: Bool { self == .vine }

    /// Moves on its own (sways, ripples), so it is drawn live rather than cached.
    var animated: Bool {
        switch self {
        case .vine, .plant, .fern, .flower, .waterDish: return true
        default: return false
        }
    }
}

struct HabitatItem: Codable, Equatable, Identifiable {
    var id: Int
    var kind: HabitatItemKind
    /// Bottom-centre (top-centre for things that hang), in scene points.
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var flipped = false
    var seed = 0
    /// Drawn in front of the spider (a foreground plant), or behind it.
    var front = false

    var rect: CGRect {
        kind.hangs ? CGRect(x: x - w / 2, y: y - h, width: w, height: h)
                   : CGRect(x: x - w / 2, y: y, width: w, height: h)
    }
}

struct Habitat: Codable, Equatable {
    var biome: Biome = .forest
    var items: [HabitatItem] = []
    var nextID = 1

    static let key = "habitat"

    static func load() -> Habitat {
        guard let data = UserDefaults.standard.data(forKey: key),
              let h = try? JSONDecoder().decode(Habitat.self, from: data) else { return .preset(.forestFloor) }
        return h
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Habitat.key) }
    }

    mutating func add(_ kind: HabitatItemKind, at p: CGPoint, scale: CGFloat = 1) -> HabitatItem {
        let size = kind.defaultSize
        let item = HabitatItem(id: nextID, kind: kind, x: p.x, y: p.y, w: size.width * scale, h: size.height * scale,
                               flipped: Bool.random(), seed: Int.random(in: 1...9999), front: false)
        nextID += 1
        items.append(item)
        return item
    }

    // MARK: Presets

    enum Preset: String, CaseIterable {
        case forestFloor, jungleCanopy, desertScrub, meadow, cave, beach, tundra, moonlit, empty
        var label: String {
            switch self {
            case .forestFloor: return "Forest floor"
            case .jungleCanopy: return "Jungle canopy"
            case .desertScrub: return "Desert scrub"
            case .meadow: return "Meadow"
            case .cave: return "Cave"
            case .beach: return "Beach"
            case .tundra: return "Tundra"
            case .moonlit: return "Moonlit"
            case .empty: return "Empty tank"
            }
        }
    }

    /// Laid out for a 900×540 scene; the view scales positions to fit.
    static func preset(_ p: Preset) -> Habitat {
        var h = Habitat()
        func put(_ kind: HabitatItemKind, _ x: CGFloat, _ y: CGFloat, scale: CGFloat = 1, flipped: Bool = false, front: Bool = false) {
            var it = h.add(kind, at: CGPoint(x: x, y: y), scale: scale)
            it.flipped = flipped
            it.front = front
            h.items[h.items.count - 1] = it
        }
        switch p {
        case .forestFloor:
            h.biome = .forest
            put(.corkBark, 80, 0, scale: 1.1)
            put(.log, 300, 0, scale: 1.2)
            put(.branch, 560, 60, scale: 1.1)
            put(.rock, 470, 0)
            put(.plant, 760, 0)
            put(.mushrooms, 380, 0, scale: 0.9)
            put(.moss, 200, 0)
            put(.leafPile, 640, 0)
            put(.fern, 180, 0, front: true)
            put(.vine, 700, 540)
        case .jungleCanopy:
            h.biome = .jungle
            put(.branch, 250, 120, scale: 1.3)
            put(.branch, 640, 220, scale: 1.2, flipped: true)
            put(.vine, 150, 540, scale: 1.2)
            put(.vine, 800, 540)
            put(.plant, 120, 0, scale: 1.3)
            put(.plant, 780, 0, scale: 1.1)
            put(.fern, 450, 0, scale: 1.2)
            put(.log, 470, 0, scale: 0.9)
            put(.moss, 300, 0)
            put(.flower, 640, 0)
            put(.fern, 700, 0, front: true)
        case .desertScrub:
            h.biome = .desert
            put(.boulder, 200, 0, scale: 1.1)
            put(.rock, 340, 0)
            put(.rock, 700, 0, scale: 0.8)
            put(.cactus, 560, 0, scale: 1.1)
            put(.cactus, 620, 0, scale: 0.7)
            put(.twigs, 430, 0)
            put(.branch, 780, 40, scale: 0.9, flipped: true)
            put(.waterDish, 90, 0)
        case .meadow:
            h.biome = .meadow
            put(.log, 200, 0)
            put(.flower, 420, 0, scale: 1.1)
            put(.flower, 520, 0, scale: 0.8)
            put(.plant, 700, 0)
            put(.rock, 330, 0, scale: 0.8)
            put(.moss, 600, 0)
            put(.branch, 820, 30, scale: 0.9, flipped: true)
            put(.flower, 150, 0, front: true)
        case .cave:
            h.biome = .cave
            put(.boulder, 160, 0, scale: 1.2)
            put(.boulder, 720, 0)
            put(.rock, 420, 0)
            put(.corkBark, 560, 0, scale: 0.9)
            put(.mushrooms, 300, 0, scale: 1.2)
            put(.mushrooms, 640, 0)
            put(.moss, 480, 0)
            put(.vine, 380, 540, scale: 0.9)
        case .beach:
            h.biome = .beach
            put(.log, 260, 0, scale: 1.3)
            put(.rock, 500, 0)
            put(.rock, 560, 0, scale: 0.6)
            put(.twigs, 700, 0)
            put(.waterDish, 820, 0, scale: 1.1)
            put(.plant, 120, 0, scale: 0.9)
        case .tundra:
            h.biome = .tundra
            put(.boulder, 300, 0)
            put(.rock, 150, 0)
            put(.log, 620, 0, scale: 1.1)
            put(.twigs, 460, 0)
            put(.moss, 760, 0)
            put(.branch, 820, 50, scale: 0.8, flipped: true)
        case .moonlit:
            h.biome = .night
            put(.log, 340, 0, scale: 1.1)
            put(.branch, 640, 90)
            put(.mushrooms, 200, 0)
            put(.plant, 800, 0)
            put(.rock, 480, 0)
            put(.vine, 150, 540)
            put(.fern, 260, 0, front: true)
        case .empty:
            h.biome = .forest
        }
        return h
    }
}

// MARK: - Surfaces

extension Habitat {
    /// The climbable parts, as loops for the spider's map, in scene points.
    func loops(standoff off: CGFloat) -> [SurfaceLoop] {
        var out: [SurfaceLoop] = []
        // Later items are in front, and hide what is behind them.
        for (i, it) in items.enumerated() where it.kind.climbable {
            let depth = items.count - i
            let r = it.rect
            let id = "item:\(it.id)"
            switch it.kind {
            case .log:
                out.append(SurfaceMap.boxLoop(id: id, rect: r.insetBy(dx: r.width * 0.06, dy: r.height * 0.1), standoff: off, depth: depth))
            case .rock, .boulder:
                out.append(SurfaceMap.boxLoop(id: id, rect: r.insetBy(dx: r.width * 0.12, dy: r.height * 0.08), standoff: off, depth: depth))
            case .corkBark, .cactus, .vine:
                out.append(SurfaceMap.boxLoop(id: id, rect: r.insetBy(dx: r.width * 0.15, dy: 0), standoff: off, depth: depth))
            case .hide:
                out.append(SurfaceMap.boxLoop(id: id, rect: r.insetBy(dx: r.width * 0.05, dy: r.height * 0.06), standoff: off, depth: depth))
            case .plant:
                // The top pad of leaves is the perch.
                let pad = CGRect(x: r.minX + r.width * 0.2, y: r.maxY - r.height * 0.26, width: r.width * 0.6, height: r.height * 0.22)
                out.append(SurfaceMap.boxLoop(id: id, rect: pad, standoff: off, depth: depth))
            case .waterDish:
                out.append(SurfaceMap.boxLoop(id: id, rect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.9), standoff: off, depth: depth))
            case .branch:
                // A stick from one bottom corner up to the other side.
                let pts = Habitat.branchPoints(r, flipped: it.flipped)
                out += SurfaceMap.stripLoops(id: id, points: pts, standoff: off, depth: depth, rect: r)
            default:
                break
            }
        }
        return out
    }

    /// The line of a branch: from its low end up to its tip, with a bend.
    static func branchPoints(_ r: CGRect, flipped: Bool) -> [V2] {
        let a = V2(r.minX + r.width * 0.05, r.minY + r.height * 0.12)
        let m = V2(r.minX + r.width * 0.5, r.minY + r.height * 0.5)
        let b = V2(r.maxX - r.width * 0.05, r.minY + r.height * 0.88)
        let pts = [a, m, b]
        return flipped ? pts.map { V2(r.maxX + r.minX - $0.x, $0.y) }.reversed() : pts
    }
}

// MARK: - Drawing

enum HabitatPainter {
    private static func rnd(_ seed: Int, _ i: Int) -> CGFloat {
        let x = sin(CGFloat(seed) * 12.9898 + CGFloat(i) * 78.233) * 43758.5453
        return x - floor(x)
    }

    // MARK: Backgrounds

    /// The scenery, filling `rect`: sky, distance, and the ground it lives on.
    /// `still` leaves out what moves (drawn by `drawAir`), so the rest can be
    /// painted once and kept.
    static func drawBackground(_ biome: Biome, in rect: CGRect, ctx: CGContext, time t: CGFloat, still: Bool = false) {
        ctx.saveGState()
        ctx.clip(to: rect)
        let (skyTop, skyBottom, far, near, ground, groundDark) = palette(biome)
        // Sky.
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [skyTop, skyBottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        let groundH = rect.height * 0.14
        let horizon = rect.minY + groundH

        switch biome {
        case .forest:
            layerTrees(rect, y: horizon, colour: far, count: 14, height: rect.height * 0.55, seed: 3, ctx: ctx)
            layerTrees(rect, y: horizon - 4, colour: near, count: 9, height: rect.height * 0.75, seed: 7, ctx: ctx)
        case .jungle:
            layerTrees(rect, y: horizon, colour: far, count: 10, height: rect.height * 0.7, seed: 5, ctx: ctx)
            layerFronds(rect, y: horizon, colour: near, seed: 11, ctx: ctx)
        case .desert:
            layerDunes(rect, y: horizon + 30, colour: far, seed: 2, ctx: ctx)
            layerDunes(rect, y: horizon + 6, colour: near, seed: 9, ctx: ctx)
            sun(rect, at: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY - rect.height * 0.22), colour: CGColor(red: 1, green: 0.9, blue: 0.6, alpha: 0.9), ctx: ctx)
        case .meadow:
            layerDunes(rect, y: horizon + 40, colour: far, seed: 4, ctx: ctx)
            layerGrass(rect, y: horizon, colour: near, seed: 8, ctx: ctx)
            sun(rect, at: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - rect.height * 0.2), colour: CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 0.9), ctx: ctx)
        case .cave:
            layerStalactites(rect, colour: far, seed: 6, ctx: ctx)
            layerDunes(rect, y: horizon + 20, colour: near, seed: 13, ctx: ctx)
        case .beach:
            // Sea, then sand.
            ctx.setFillColor(far)
            ctx.fill(CGRect(x: rect.minX, y: horizon, width: rect.width, height: rect.height * 0.28))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
            for k in 0..<5 {
                let y = horizon + rect.height * 0.04 + CGFloat(k) * rect.height * 0.05 + sin(t * 0.7 + CGFloat(k)) * 2
                ctx.fill(CGRect(x: rect.minX + CGFloat(k * 37 % 90), y: y, width: rect.width * 0.35, height: 1.5))
            }
            sun(rect, at: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.25), colour: CGColor(red: 1, green: 0.92, blue: 0.7, alpha: 0.9), ctx: ctx)
            layerDunes(rect, y: horizon + 4, colour: near, seed: 12, ctx: ctx)
        case .tundra:
            layerDunes(rect, y: horizon + 50, colour: far, seed: 15, ctx: ctx)
            layerTrees(rect, y: horizon, colour: near, count: 6, height: rect.height * 0.5, seed: 16, ctx: ctx)
        case .night:
            // The moon (the stars twinkle, so they are drawn live).
            let mc = CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.2)
            ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.8, alpha: 0.95))
            ctx.fillEllipse(in: CGRect(x: mc.x - 22, y: mc.y - 22, width: 44, height: 44))
            ctx.setFillColor(skyTop)
            ctx.fillEllipse(in: CGRect(x: mc.x - 8, y: mc.y - 16, width: 38, height: 38))
            layerTrees(rect, y: horizon, colour: far, count: 12, height: rect.height * 0.6, seed: 17, ctx: ctx)
        }

        if !still { drawAir(biome, in: rect, ctx: ctx, time: t) }

        // The ground: substrate with a darker band at the bottom and specks.
        ctx.setFillColor(ground)
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: groundH))
        ctx.setFillColor(groundDark)
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: groundH * 0.35))
        for k in 0..<60 {
            let x = rect.minX + rnd(41, k) * rect.width
            let y = rect.minY + rnd(42, k) * groundH
            let r = 1 + rnd(43, k) * 2
            ctx.setFillColor(k % 2 == 0 ? groundDark : CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
        }
        ctx.restoreGState()
    }

    /// What moves in the air, by biome: leaves drifting down, pollen, dust
    /// in the cave light, snow, fireflies at night. Drawn live every frame.
    static func drawAir(_ biome: Biome, in rect: CGRect, ctx: CGContext, time t: CGFloat) {
        let groundH = rect.height * 0.14
        let horizon = rect.minY + groundH
        ctx.saveGState()
        ctx.clip(to: rect)
        if biome == .tundra {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
            for k in 0..<40 {
                let x = rect.minX + rnd(21, k) * rect.width + sin(t * 0.5 + CGFloat(k)) * 6
                let y = rect.maxY - ((rnd(22, k) * rect.height + t * 18 * (0.6 + rnd(23, k))).truncatingRemainder(dividingBy: rect.height))
                let r = 1.2 + rnd(24, k) * 1.6
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        if biome == .night {
            for k in 0..<70 {
                let x = rect.minX + rnd(31, k) * rect.width
                let y = horizon + rnd(32, k) * (rect.height - groundH) * 0.9
                let a = 0.4 + 0.6 * abs(sin(t * (0.5 + rnd(33, k)) + CGFloat(k)))
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.9, alpha: a))
                let r = 0.8 + rnd(34, k) * 1.2
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        switch biome {
        case .forest, .jungle:
            for k in 0..<7 {
                let fall = ((t * (8 + rnd(51, k) * 10)) + rnd(52, k) * rect.height).truncatingRemainder(dividingBy: rect.height + 20)
                let x = rect.minX + rnd(53, k) * rect.width + sin(t * 0.9 + CGFloat(k)) * 14
                let y = rect.maxY - fall
                ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: t * (0.6 + rnd(54, k)))
                ctx.setFillColor(biome == .forest ? CGColor(red: 0.8, green: 0.55, blue: 0.25, alpha: 0.8) : CGColor(red: 0.45, green: 0.7, blue: 0.35, alpha: 0.8))
                ctx.fillEllipse(in: CGRect(x: -5, y: -2.5, width: 10, height: 5))
                ctx.restoreGState()
            }
        case .meadow, .beach:
            ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 0.6))
            for k in 0..<18 {
                let x = rect.minX + ((rnd(61, k) * rect.width + t * (6 + rnd(62, k) * 8))).truncatingRemainder(dividingBy: rect.width)
                let y = horizon + rnd(63, k) * (rect.height - groundH) * 0.7 + sin(t * 0.8 + CGFloat(k)) * 8
                ctx.fillEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
            }
        case .cave:
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.9, alpha: 0.25))
            for k in 0..<30 {
                let x = rect.minX + rect.width * (0.3 + rnd(71, k) * 0.4) + sin(t * 0.3 + CGFloat(k)) * 10
                let y = rect.minY + ((rnd(72, k) * rect.height + t * 4)).truncatingRemainder(dividingBy: rect.height)
                ctx.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
            }
        case .night:
            for k in 0..<9 {
                let x = rect.minX + rnd(81, k) * rect.width + sin(t * (0.4 + rnd(82, k) * 0.4) + CGFloat(k)) * 30
                let y = horizon + rnd(83, k) * rect.height * 0.35 + cos(t * 0.5 + CGFloat(k) * 2) * 12
                let glow = 0.5 + 0.5 * sin(t * (1.5 + rnd(84, k)) + CGFloat(k))
                ctx.setFillColor(CGColor(red: 0.8, green: 1, blue: 0.4, alpha: 0.25 * glow))
                ctx.fillEllipse(in: CGRect(x: x - 6, y: y - 6, width: 12, height: 12))
                ctx.setFillColor(CGColor(red: 0.9, green: 1, blue: 0.6, alpha: 0.9 * glow))
                ctx.fillEllipse(in: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6))
            }
        default:
            break
        }
        ctx.restoreGState()
    }

    /// The colours of a biome: sky top and bottom, far and near scenery,
    /// ground and its dark band.
    private static func palette(_ b: Biome) -> (CGColor, CGColor, CGColor, CGColor, CGColor, CGColor) {
        func c(_ r: CGFloat, _ g: CGFloat, _ bl: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: bl, alpha: a) }
        switch b {
        case .forest: return (c(0.62, 0.80, 0.90), c(0.86, 0.92, 0.84), c(0.42, 0.58, 0.44), c(0.26, 0.42, 0.30), c(0.42, 0.32, 0.22), c(0.30, 0.22, 0.15))
        case .jungle: return (c(0.55, 0.78, 0.72), c(0.80, 0.92, 0.75), c(0.18, 0.48, 0.34), c(0.10, 0.36, 0.24), c(0.36, 0.30, 0.20), c(0.24, 0.20, 0.13))
        case .desert: return (c(0.55, 0.72, 0.92), c(0.98, 0.86, 0.66), c(0.88, 0.70, 0.46), c(0.80, 0.58, 0.36), c(0.90, 0.78, 0.55), c(0.74, 0.60, 0.40))
        case .meadow: return (c(0.60, 0.80, 0.96), c(0.90, 0.96, 0.90), c(0.60, 0.78, 0.48), c(0.40, 0.66, 0.34), c(0.46, 0.36, 0.24), c(0.32, 0.25, 0.17))
        case .cave: return (c(0.12, 0.11, 0.14), c(0.22, 0.20, 0.24), c(0.30, 0.27, 0.32), c(0.20, 0.18, 0.22), c(0.36, 0.32, 0.30), c(0.22, 0.20, 0.19))
        case .beach: return (c(0.55, 0.78, 0.96), c(0.86, 0.94, 0.98), c(0.25, 0.60, 0.78), c(0.95, 0.88, 0.70), c(0.93, 0.85, 0.66), c(0.80, 0.70, 0.52))
        case .tundra: return (c(0.72, 0.80, 0.88), c(0.92, 0.94, 0.96), c(0.78, 0.84, 0.90), c(0.42, 0.50, 0.56), c(0.90, 0.92, 0.95), c(0.72, 0.76, 0.82))
        case .night: return (c(0.05, 0.06, 0.16), c(0.14, 0.16, 0.34), c(0.10, 0.12, 0.22), c(0.06, 0.08, 0.16), c(0.20, 0.18, 0.20), c(0.12, 0.11, 0.13))
        }
    }

    private static func sun(_ rect: CGRect, at c: CGPoint, colour: CGColor, ctx: CGContext) {
        for (r, a) in [(CGFloat(46), 0.12), (34, 0.2), (22, 1.0)] {
            ctx.setFillColor(colour.copy(alpha: a * colour.alpha)!)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
    }

    private static func layerTrees(_ rect: CGRect, y: CGFloat, colour: CGColor, count: Int, height: CGFloat, seed: Int, ctx: CGContext) {
        ctx.setFillColor(colour)
        for k in 0..<count {
            let x = rect.minX + (CGFloat(k) + rnd(seed, k) * 0.8) / CGFloat(count) * rect.width
            let h = height * (0.6 + rnd(seed + 1, k) * 0.5)
            let w = h * 0.36
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x - w / 2, y: y))
            p.addLine(to: CGPoint(x: x, y: y + h))
            p.addLine(to: CGPoint(x: x + w / 2, y: y))
            p.closeSubpath()
            // A second tier for a firry look.
            p.move(to: CGPoint(x: x - w * 0.38, y: y + h * 0.4))
            p.addLine(to: CGPoint(x: x, y: y + h * 1.05))
            p.addLine(to: CGPoint(x: x + w * 0.38, y: y + h * 0.4))
            p.closeSubpath()
            ctx.addPath(p); ctx.fillPath()
            ctx.fill(CGRect(x: x - 2, y: y - 2, width: 4, height: 6))
        }
    }

    private static func layerFronds(_ rect: CGRect, y: CGFloat, colour: CGColor, seed: Int, ctx: CGContext) {
        ctx.setStrokeColor(colour)
        ctx.setLineCap(.round)
        for k in 0..<9 {
            let x = rect.minX + (CGFloat(k) + 0.5) / 9 * rect.width
            let h = rect.height * (0.35 + rnd(seed, k) * 0.35)
            for j in 0..<5 {
                let a = CGFloat(j - 2) * 0.35 + (rnd(seed + 1, k * 7 + j) - 0.5) * 0.2
                ctx.setLineWidth(6 - CGFloat(j % 3))
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addQuadCurve(to: CGPoint(x: x + sin(a) * h, y: y + cos(a) * h), control: CGPoint(x: x + sin(a) * h * 0.3, y: y + h * 0.8))
                ctx.strokePath()
            }
        }
    }

    private static func layerDunes(_ rect: CGRect, y: CGFloat, colour: CGColor, seed: Int, ctx: CGContext) {
        ctx.setFillColor(colour)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: y))
        let n = 6
        for k in 0...n {
            let x0 = rect.minX + CGFloat(k) / CGFloat(n) * rect.width
            let x1 = rect.minX + CGFloat(k + 1) / CGFloat(n) * rect.width
            let h = rect.height * (0.04 + rnd(seed, k) * 0.12)
            p.addQuadCurve(to: CGPoint(x: x1, y: y + (k % 2 == 0 ? 0 : h * 0.3)), control: CGPoint(x: (x0 + x1) / 2, y: y + h))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        ctx.addPath(p); ctx.fillPath()
    }

    private static func layerGrass(_ rect: CGRect, y: CGFloat, colour: CGColor, seed: Int, ctx: CGContext) {
        ctx.setStrokeColor(colour)
        ctx.setLineCap(.round)
        ctx.setLineWidth(2)
        for k in 0..<90 {
            let x = rect.minX + rnd(seed, k) * rect.width
            let h = 8 + rnd(seed + 1, k) * 22
            let lean = (rnd(seed + 2, k) - 0.5) * 10
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: y - 2))
            ctx.addQuadCurve(to: CGPoint(x: x + lean, y: y + h), control: CGPoint(x: x + lean * 0.2, y: y + h * 0.6))
            ctx.strokePath()
        }
    }

    private static func layerStalactites(_ rect: CGRect, colour: CGColor, seed: Int, ctx: CGContext) {
        ctx.setFillColor(colour)
        for k in 0..<16 {
            let x = rect.minX + (CGFloat(k) + rnd(seed, k)) / 16 * rect.width
            let h = rect.height * (0.08 + rnd(seed + 1, k) * 0.3)
            let w = 10 + rnd(seed + 2, k) * 24
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x - w / 2, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + w / 2, y: rect.maxY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY - h))
            p.closeSubpath()
            ctx.addPath(p); ctx.fillPath()
        }
    }

    // MARK: The glass

    /// Rounded corners, a faint tint and highlights, so it reads as a tank.
    static func drawGlass(in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
        ctx.setLineWidth(3)
        ctx.addPath(path); ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        ctx.setLineWidth(1.5)
        ctx.addPath(path); ctx.strokePath()
        // A diagonal sheen.
        ctx.addPath(path); ctx.clip()
        let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.10), CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY - rect.height * 0.5), options: [])
        ctx.restoreGState()
    }

    // MARK: Items

    static func draw(_ it: HabitatItem, biome: Biome, time t: CGFloat, selected: Bool, ctx: CGContext) {
        let r = it.rect
        ctx.saveGState()
        if it.flipped {
            ctx.translateBy(x: r.midX, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.translateBy(x: -r.midX, y: 0)
        }
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        let outline = CGColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 0.9)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(1.8)
        let s = it.seed
        switch it.kind {
        case .log: drawLog(r, s, ctx)
        case .hide: drawHide(r, s, ctx)
        case .branch: drawBranch(r, s, ctx)
        case .rock, .boulder: drawRock(r, s, biome, ctx)
        case .corkBark: drawBark(r, s, ctx)
        case .cactus: drawCactus(r, s, ctx)
        case .vine: drawVine(r, s, t, ctx)
        case .plant: drawPlant(r, s, t, ctx)
        case .fern: drawFern(r, s, t, ctx)
        case .flower: drawFlowers(r, s, t, ctx)
        case .mushrooms: drawMushrooms(r, s, ctx)
        case .moss: drawMoss(r, s, ctx)
        case .leafPile: drawLeafPile(r, s, biome, ctx)
        case .waterDish: drawWaterDish(r, s, t, ctx)
        case .twigs: drawTwigs(r, s, ctx)
        }
        ctx.restoreGState()
        if selected {
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(red: 0.2, green: 0.55, blue: 1, alpha: 0.9))
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [5, 4])
            ctx.stroke(r.insetBy(dx: -3, dy: -3))
            ctx.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 1, alpha: 0.9))
            ctx.fill(CGRect(x: r.maxX - 2, y: r.maxY - 2, width: 9, height: 9))
            ctx.restoreGState()
        }
    }

    private static func wood(_ s: Int) -> (CGColor, CGColor, CGColor) {
        let v = rnd(s, 1) * 0.12
        return (CGColor(red: 0.55 + v, green: 0.38 + v * 0.6, blue: 0.22, alpha: 1),
                CGColor(red: 0.40 + v, green: 0.27 + v * 0.5, blue: 0.15, alpha: 1),
                CGColor(red: 0.70 + v, green: 0.52 + v * 0.6, blue: 0.32, alpha: 1))
    }

    private static func drawLog(_ r: CGRect, _ s: Int, _ ctx: CGContext) {
        let (mid, dark, light) = wood(s)
        let body = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        ctx.addPath(body); ctx.setFillColor(mid); ctx.fillPath()
        // Bark grain.
        ctx.saveGState(); ctx.addPath(body); ctx.clip()
        ctx.setStrokeColor(dark); ctx.setLineWidth(1.2)
        for k in 0..<7 {
            let y = r.minY + (CGFloat(k) + 0.5) / 7 * r.height
            ctx.beginPath(); ctx.move(to: CGPoint(x: r.minX + 8, y: y))
            ctx.addQuadCurve(to: CGPoint(x: r.maxX - 8, y: y + (rnd(s, k) - 0.5) * 4), control: CGPoint(x: r.midX, y: y + (rnd(s + 1, k) - 0.5) * 6))
            ctx.strokePath()
        }
        // A knot or two.
        for k in 0..<2 {
            let c = CGPoint(x: r.minX + r.width * (0.25 + rnd(s + 2, k) * 0.5), y: r.midY + (rnd(s + 3, k) - 0.5) * r.height * 0.4)
            ctx.setFillColor(dark); ctx.fillEllipse(in: CGRect(x: c.x - 5, y: c.y - 3.5, width: 10, height: 7))
            ctx.setFillColor(light); ctx.fillEllipse(in: CGRect(x: c.x - 2.5, y: c.y - 1.5, width: 5, height: 3))
        }
        ctx.restoreGState()
        // The cut end: rings.
        let end = CGRect(x: r.maxX - r.height * 0.45, y: r.minY + 2, width: r.height * 0.42, height: r.height - 4)
        ctx.setFillColor(light); ctx.fillEllipse(in: end)
        ctx.setStrokeColor(dark); ctx.setLineWidth(1)
        for k in 1...3 { ctx.strokeEllipse(in: end.insetBy(dx: CGFloat(k) * end.width * 0.14, dy: CGFloat(k) * end.height * 0.14)) }
        ctx.setStrokeColor(CGColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 0.9)); ctx.setLineWidth(1.8)
        ctx.addPath(body); ctx.strokePath()
        ctx.strokeEllipse(in: end)
    }

    private static func drawHide(_ r: CGRect, _ s: Int, _ ctx: CGContext) {
        let (mid, dark, _) = wood(s)
        let body = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        ctx.addPath(body); ctx.setFillColor(mid); ctx.fillPath()
        // The hollow: a dark opening at the near end.
        let hole = CGRect(x: r.minX + 4, y: r.minY + r.height * 0.15, width: r.height * 0.55, height: r.height * 0.7)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.05, blue: 0.03, alpha: 1)); ctx.fillEllipse(in: hole)
        ctx.saveGState(); ctx.addPath(body); ctx.clip()
        ctx.setStrokeColor(dark); ctx.setLineWidth(1.2)
        for k in 0..<5 {
            let y = r.minY + (CGFloat(k) + 0.5) / 5 * r.height
            ctx.beginPath(); ctx.move(to: CGPoint(x: hole.maxX + 6, y: y)); ctx.addLine(to: CGPoint(x: r.maxX - 6, y: y + (rnd(s, k) - 0.5) * 5)); ctx.strokePath()
        }
        ctx.restoreGState()
        ctx.addPath(body); ctx.strokePath()
        ctx.strokeEllipse(in: hole)
    }

    private static func drawBranch(_ r: CGRect, _ s: Int, _ ctx: CGContext) {
        let (mid, dark, _) = wood(s)
        let pts = Habitat.branchPoints(r, flipped: false)
        let thick = max(6, r.height * 0.11)
        // Main stick, tapering.
        for (i, (col, w)) in [(CGColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 0.9), thick + 3.6), (mid, thick)].enumerated() {
            ctx.setStrokeColor(col)
            for j in 0..<(pts.count - 1) {
                ctx.setLineWidth(w * (1 - CGFloat(j) * 0.25))
                ctx.beginPath(); ctx.move(to: pts[j].point); ctx.addLine(to: pts[j + 1].point); ctx.strokePath()
            }
            _ = i
        }
        // Side twigs with a few leaves.
        ctx.setStrokeColor(dark)
        for k in 0..<4 {
            let u = 0.25 + CGFloat(k) * 0.18
            let base = V2.lerp(pts[0], pts[2], u) + V2(0, r.height * 0.06)
            let dir = V2(0.4 + (rnd(s, k) - 0.5) * 0.6, 1).normalized * (r.height * (0.18 + rnd(s + 1, k) * 0.15))
            ctx.setLineWidth(2.2)
            ctx.beginPath(); ctx.move(to: base.point); ctx.addLine(to: (base + dir).point); ctx.strokePath()
            let leaf = base + dir
            ctx.setFillColor(CGColor(red: 0.35, green: 0.6, blue: 0.3, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: leaf.x - 5, y: leaf.y - 3, width: 10, height: 6))
        }
    }

    private static func drawRock(_ r: CGRect, _ s: Int, _ biome: Biome, _ ctx: CGContext) {
        let base: (CGFloat, CGFloat, CGFloat) = biome == .desert ? (0.72, 0.55, 0.4) : (biome == .cave ? (0.42, 0.40, 0.44) : (0.55, 0.55, 0.52))
        let v = (rnd(s, 1) - 0.5) * 0.1
        let fill = CGColor(red: base.0 + v, green: base.1 + v, blue: base.2 + v, alpha: 1)
        let p = CGMutablePath()
        let n = 8
        var pts: [CGPoint] = []
        for k in 0..<n {
            let a = CGFloat(k) / CGFloat(n) * 2 * .pi
            let rad = 1 - rnd(s, k) * 0.18
            pts.append(CGPoint(x: r.midX + cos(a) * r.width / 2 * rad, y: r.midY + sin(a) * r.height / 2 * rad * (sin(a) < 0 ? 0.55 : 1)))
        }
        p.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
        for k in 0..<n {
            let nx = pts[(k + 1) % n]
            p.addQuadCurve(to: CGPoint(x: (pts[k].x + nx.x) / 2, y: (pts[k].y + nx.y) / 2), control: pts[k])
        }
        p.closeSubpath()
        ctx.addPath(p); ctx.setFillColor(fill); ctx.fillPath()
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.2, y: r.midY, width: r.width * 0.45, height: r.height * 0.4))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
        ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.22))
        ctx.restoreGState()
        ctx.addPath(p); ctx.strokePath()
    }

    private static func drawBark(_ r: CGRect, _ s: Int, _ ctx: CGContext) {
        let (mid, dark, light) = wood(s)
        let p = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(p); ctx.setFillColor(mid); ctx.fillPath()
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        // Deep vertical fissures and lighter ridges.
        for k in 0..<9 {
            let x = r.minX + (CGFloat(k) + 0.5) / 9 * r.width
            ctx.setStrokeColor(k % 2 == 0 ? dark : light)
            ctx.setLineWidth(k % 2 == 0 ? 3 : 1.5)
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: r.minY))
            ctx.addCurve(to: CGPoint(x: x + (rnd(s, k) - 0.5) * 8, y: r.maxY),
                         control1: CGPoint(x: x + (rnd(s + 1, k) - 0.5) * 12, y: r.minY + r.height * 0.33),
                         control2: CGPoint(x: x + (rnd(s + 2, k) - 0.5) * 12, y: r.minY + r.height * 0.66))
            ctx.strokePath()
        }
        ctx.restoreGState()
        ctx.addPath(p); ctx.strokePath()
    }

    private static func drawCactus(_ r: CGRect, _ s: Int, _ ctx: CGContext) {
        let green = CGColor(red: 0.36, green: 0.62, blue: 0.40, alpha: 1)
        let dark = CGColor(red: 0.24, green: 0.46, blue: 0.30, alpha: 1)
        let w = r.width * 0.55
        let trunk = CGPath(roundedRect: CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height), cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
        ctx.addPath(trunk); ctx.setFillColor(green); ctx.fillPath()
        // Arms.
        for (side, h) in [(CGFloat(-1), 0.55), (1, 0.7)] {
            let aw = w * 0.6
            let ay = r.minY + r.height * CGFloat(h) * 0.6
            let arm = CGMutablePath()
            arm.addRoundedRect(in: CGRect(x: side > 0 ? r.midX + w / 2 - 2 : r.midX - w / 2 - aw * 1.2 + 2, y: ay, width: aw * 1.2, height: aw), cornerWidth: aw / 2, cornerHeight: aw / 2)
            let ax = side > 0 ? r.midX + w / 2 + aw * 0.6 : r.midX - w / 2 - aw * 0.6
            arm.addRoundedRect(in: CGRect(x: ax - aw / 2, y: ay, width: aw, height: r.height * CGFloat(h) * 0.5), cornerWidth: aw / 2, cornerHeight: aw / 2)
            ctx.addPath(arm); ctx.setFillColor(green); ctx.fillPath()
            ctx.addPath(arm); ctx.strokePath()
        }
        ctx.addPath(trunk); ctx.setFillColor(green); ctx.fillPath()
        ctx.saveGState(); ctx.addPath(trunk); ctx.clip()
        ctx.setStrokeColor(dark); ctx.setLineWidth(1.2)
        for k in 0..<3 {
            let x = r.midX - w / 2 + (CGFloat(k) + 0.5) / 3 * w
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addLine(to: CGPoint(x: x, y: r.maxY)); ctx.strokePath()
        }
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 0.9))
        ctx.addPath(trunk); ctx.strokePath()
        // Spines.
        ctx.setStrokeColor(CGColor(red: 0.95, green: 0.92, blue: 0.75, alpha: 1)); ctx.setLineWidth(1)
        for k in 0..<14 {
            let y = r.minY + (rnd(s, k)) * r.height
            let side: CGFloat = k % 2 == 0 ? 1 : -1
            let x = r.midX + side * w / 2
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + side * 4, y: y + 2)); ctx.strokePath()
        }
    }

    private static func drawVine(_ r: CGRect, _ s: Int, _ t: CGFloat, _ ctx: CGContext) {
        let green = CGColor(red: 0.30, green: 0.55, blue: 0.30, alpha: 1)
        let dark = CGColor(red: 0.20, green: 0.40, blue: 0.22, alpha: 1)
        let sway = sin(t * 0.6 + CGFloat(s % 7)) * 3
        // Two twined stems from the top.
        for (col, w, off) in [(dark, CGFloat(5), CGFloat(-2)), (green, 4, 2)] {
            ctx.setStrokeColor(col); ctx.setLineWidth(w)
            ctx.beginPath(); ctx.move(to: CGPoint(x: r.midX + off, y: r.maxY))
            ctx.addCurve(to: CGPoint(x: r.midX - off + sway, y: r.minY),
                         control1: CGPoint(x: r.midX + off * 3, y: r.maxY - r.height * 0.33),
                         control2: CGPoint(x: r.midX - off * 3 + sway, y: r.maxY - r.height * 0.66))
            ctx.strokePath()
        }
        // Leaves along it.
        for k in 0..<Int(r.height / 22) {
            let u = (CGFloat(k) + 0.5) / CGFloat(max(1, Int(r.height / 22)))
            let y = r.maxY - u * r.height
            let side: CGFloat = k % 2 == 0 ? 1 : -1
            let x = r.midX + side * 4 + sway * u
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: side * (0.6 + (rnd(s, k) - 0.5) * 0.4) + sin(t * 0.8 + CGFloat(k)) * 0.06)
            ctx.setFillColor(k % 3 == 0 ? dark : green)
            ctx.fillEllipse(in: CGRect(x: 0, y: -4, width: 14, height: 8))
            ctx.setStrokeColor(dark); ctx.setLineWidth(0.8)
            ctx.beginPath(); ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: 13, y: 0)); ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private static func drawPlant(_ r: CGRect, _ s: Int, _ t: CGFloat, _ ctx: CGContext) {
        let green = CGColor(red: 0.30, green: 0.58, blue: 0.32, alpha: 1)
        let dark = CGColor(red: 0.20, green: 0.42, blue: 0.24, alpha: 1)
        let light = CGColor(red: 0.45, green: 0.72, blue: 0.40, alpha: 1)
        // A pot of soil at the base.
        ctx.setFillColor(CGColor(red: 0.62, green: 0.40, blue: 0.28, alpha: 1))
        let pot = CGRect(x: r.midX - r.width * 0.22, y: r.minY, width: r.width * 0.44, height: r.height * 0.2)
        ctx.fill(pot); ctx.stroke(pot)
        ctx.setFillColor(CGColor(red: 0.30, green: 0.22, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: pot.minX + 2, y: pot.maxY - 4, width: pot.width - 4, height: 4))
        // Stems fanning up, leaves at the ends, a broad pad at the top.
        for k in 0..<7 {
            let a = CGFloat(k - 3) * 0.28 + (rnd(s, k) - 0.5) * 0.15 + sin(t * 0.7 + CGFloat(k)) * 0.03
            let len = r.height * (0.5 + rnd(s + 1, k) * 0.35)
            let tip = CGPoint(x: r.midX + sin(a) * len, y: pot.maxY + cos(a) * len)
            ctx.setStrokeColor(dark); ctx.setLineWidth(2.5)
            ctx.beginPath(); ctx.move(to: CGPoint(x: r.midX, y: pot.maxY))
            ctx.addQuadCurve(to: tip, control: CGPoint(x: r.midX + sin(a) * len * 0.3, y: pot.maxY + len * 0.6)); ctx.strokePath()
            ctx.saveGState()
            ctx.translateBy(x: tip.x, y: tip.y)
            ctx.rotate(by: -a * 0.6)
            ctx.setFillColor(k % 2 == 0 ? green : light)
            ctx.fillEllipse(in: CGRect(x: -r.width * 0.12, y: -r.height * 0.06, width: r.width * 0.24, height: r.height * 0.13))
            ctx.strokeEllipse(in: CGRect(x: -r.width * 0.12, y: -r.height * 0.06, width: r.width * 0.24, height: r.height * 0.13))
            ctx.restoreGState()
        }
        // The pad on top it can sit on.
        let pad = CGRect(x: r.minX + r.width * 0.2, y: r.maxY - r.height * 0.26, width: r.width * 0.6, height: r.height * 0.22)
        ctx.setFillColor(green); ctx.fillEllipse(in: pad); ctx.strokeEllipse(in: pad)
        ctx.setStrokeColor(dark); ctx.setLineWidth(1)
        ctx.beginPath(); ctx.move(to: CGPoint(x: pad.minX + 6, y: pad.midY)); ctx.addLine(to: CGPoint(x: pad.maxX - 6, y: pad.midY)); ctx.strokePath()
    }

    private static func drawFern(_ r: CGRect, _ s: Int, _ t: CGFloat, _ ctx: CGContext) {
        let green = CGColor(red: 0.26, green: 0.55, blue: 0.30, alpha: 1)
        let dark = CGColor(red: 0.16, green: 0.38, blue: 0.20, alpha: 1)
        for k in 0..<7 {
            let a = CGFloat(k - 3) * 0.32 + (rnd(s, k) - 0.5) * 0.2 + sin(t * 0.8 + CGFloat(k) * 0.7) * 0.04
            let len = r.height * (0.7 + rnd(s + 1, k) * 0.3)
            let base = CGPoint(x: r.midX, y: r.minY)
            let tip = CGPoint(x: base.x + sin(a) * len * 1.1, y: base.y + cos(a) * len)
            ctx.setStrokeColor(dark); ctx.setLineWidth(2)
            ctx.beginPath(); ctx.move(to: base); ctx.addQuadCurve(to: tip, control: CGPoint(x: base.x + sin(a) * len * 0.3, y: base.y + len * 0.75)); ctx.strokePath()
            // Leaflets along the frond.
            ctx.setFillColor(k % 2 == 0 ? green : dark)
            for j in 1..<9 {
                let u = CGFloat(j) / 9
                let p = CGPoint(x: base.x + (tip.x - base.x) * u + sin(a) * len * 0.3 * (1 - u) * u * 2, y: base.y + (tip.y - base.y) * u + len * 0.2 * (1 - u) * u * 2)
                let lw = (1 - u) * 9 + 3
                ctx.saveGState(); ctx.translateBy(x: p.x, y: p.y); ctx.rotate(by: -a * 0.5)
                ctx.fillEllipse(in: CGRect(x: -lw, y: -2.2, width: lw * 2, height: 4.4))
                ctx.restoreGState()
            }
        }
    }

    private static func drawFlowers(_ r: CGRect, _ s: Int, _ t: CGFloat, _ ctx: CGContext) {
        let stem = CGColor(red: 0.30, green: 0.55, blue: 0.30, alpha: 1)
        let petals: [CGColor] = [CGColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1), CGColor(red: 0.98, green: 0.80, blue: 0.30, alpha: 1),
                                 CGColor(red: 0.70, green: 0.55, blue: 0.95, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 1)]
        for k in 0..<4 {
            let x = r.minX + r.width * (0.2 + CGFloat(k) * 0.2) + (rnd(s, k) - 0.5) * 10
            let h = r.height * (0.6 + rnd(s + 1, k) * 0.4)
            let lean = sin(t * 0.9 + CGFloat(k)) * 2
            ctx.setStrokeColor(stem); ctx.setLineWidth(2)
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addQuadCurve(to: CGPoint(x: x + lean, y: r.minY + h), control: CGPoint(x: x + lean * 0.3, y: r.minY + h * 0.5)); ctx.strokePath()
            ctx.setFillColor(stem)
            ctx.fillEllipse(in: CGRect(x: x + 1, y: r.minY + h * 0.4, width: 9, height: 4))
            let c = CGPoint(x: x + lean, y: r.minY + h)
            ctx.setFillColor(petals[(k + s) % petals.count])
            for q in 0..<6 {
                let a = CGFloat(q) / 6 * 2 * .pi
                ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * 5 - 3.5, y: c.y + sin(a) * 5 - 3.5, width: 7, height: 7))
            }
            ctx.setFillColor(CGColor(red: 0.98, green: 0.85, blue: 0.35, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
            ctx.strokeEllipse(in: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
        }
    }

    private static func drawMushrooms(_ r: CGRect, _ s: Int, _ ctx: CGContext) {
        for k in 0..<3 {
            let x = r.minX + r.width * (0.2 + CGFloat(k) * 0.3)
            let h = r.height * (0.55 + rnd(s, k) * 0.45)
            let cw = r.width * (0.22 + rnd(s + 1, k) * 0.12)
            ctx.setFillColor(CGColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1))
            let stalk = CGRect(x: x - cw * 0.2, y: r.minY, width: cw * 0.4, height: h * 0.7)
            ctx.fill(stalk); ctx.stroke(stalk)
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: x - cw / 2, y: r.minY + h * 0.6))
            cap.addQuadCurve(to: CGPoint(x: x + cw / 2, y: r.minY + h * 0.6), control: CGPoint(x: x, y: r.minY + h * 1.25))
            cap.closeSubpath()
            ctx.addPath(cap); ctx.setFillColor(k % 2 == 0 ? CGColor(red: 0.85, green: 0.30, blue: 0.22, alpha: 1) : CGColor(red: 0.75, green: 0.55, blue: 0.35, alpha: 1)); ctx.fillPath()
            ctx.addPath(cap); ctx.strokePath()
            if k % 2 == 0 {
                ctx.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1))
                for q in 0..<3 { ctx.fillEllipse(in: CGRect(x: x - cw * 0.3 + CGFloat(q) * cw * 0.3, y: r.minY + h * (0.7 + CGFloat(q % 2) * 0.12), width: 3, height: 3)) }
            }
        }
    }

    private static func drawMoss(_ r: CGRect, _ s: Int, _ ctx: CGContext) {
        ctx.setFillColor(CGColor(red: 0.36, green: 0.62, blue: 0.30, alpha: 1))
        for k in 0..<12 {
            let x = r.minX + rnd(s, k) * r.width
            let w = 10 + rnd(s + 1, k) * 20
            let h = r.height * (0.5 + rnd(s + 2, k) * 0.5)
            ctx.fillEllipse(in: CGRect(x: x - w / 2, y: r.minY - h * 0.3, width: w, height: h * 1.3))
        }
        ctx.setFillColor(CGColor(red: 0.50, green: 0.75, blue: 0.38, alpha: 1))
        for k in 0..<8 {
            let x = r.minX + rnd(s + 3, k) * r.width
            ctx.fillEllipse(in: CGRect(x: x - 5, y: r.minY + r.height * 0.3, width: 10, height: r.height * 0.5))
        }
    }

    private static func drawLeafPile(_ r: CGRect, _ s: Int, _ biome: Biome, _ ctx: CGContext) {
        let cols: [CGColor] = biome == .tundra ? [CGColor(red: 0.6, green: 0.55, blue: 0.45, alpha: 1), CGColor(red: 0.7, green: 0.62, blue: 0.5, alpha: 1)]
            : [CGColor(red: 0.75, green: 0.45, blue: 0.2, alpha: 1), CGColor(red: 0.85, green: 0.6, blue: 0.25, alpha: 1), CGColor(red: 0.6, green: 0.35, blue: 0.18, alpha: 1)]
        ctx.setLineWidth(1)
        for k in 0..<16 {
            let x = r.minX + rnd(s, k) * r.width
            let y = r.minY + rnd(s + 1, k) * r.height * 0.8
            ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: (rnd(s + 2, k) - 0.5) * 1.2)
            ctx.setFillColor(cols[k % cols.count])
            ctx.fillEllipse(in: CGRect(x: -7, y: -3.5, width: 14, height: 7)); ctx.strokeEllipse(in: CGRect(x: -7, y: -3.5, width: 14, height: 7))
            ctx.restoreGState()
        }
    }

    private static func drawWaterDish(_ r: CGRect, _ s: Int, _ t: CGFloat, _ ctx: CGContext) {
        let dish = CGPath(roundedRect: r, cornerWidth: r.height * 0.4, cornerHeight: r.height * 0.4, transform: nil)
        ctx.addPath(dish); ctx.setFillColor(CGColor(red: 0.55, green: 0.52, blue: 0.5, alpha: 1)); ctx.fillPath()
        let water = CGRect(x: r.minX + 5, y: r.minY + r.height * 0.3, width: r.width - 10, height: r.height * 0.5)
        ctx.setFillColor(CGColor(red: 0.45, green: 0.72, blue: 0.9, alpha: 0.9)); ctx.fillEllipse(in: water)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6)); ctx.setLineWidth(1)
        for k in 0..<2 {
            let ph = t * 1.5 + CGFloat(k) * 2
            ctx.strokeEllipse(in: water.insetBy(dx: water.width * (0.2 + 0.15 * abs(sin(ph))), dy: water.height * (0.2 + 0.15 * abs(sin(ph)))))
        }
        ctx.setStrokeColor(CGColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 0.9)); ctx.setLineWidth(1.8)
        ctx.addPath(dish); ctx.strokePath()
    }

    private static func drawTwigs(_ r: CGRect, _ s: Int, _ ctx: CGContext) {
        let (mid, dark, _) = wood(s)
        for k in 0..<5 {
            let x0 = r.minX + rnd(s, k) * r.width * 0.6
            let y0 = r.minY + rnd(s + 1, k) * r.height * 0.5
            let len = r.width * (0.3 + rnd(s + 2, k) * 0.4)
            let a = (rnd(s + 3, k) - 0.5) * 0.7
            ctx.setStrokeColor(k % 2 == 0 ? mid : dark); ctx.setLineWidth(2.5 + rnd(s + 4, k) * 2)
            ctx.beginPath(); ctx.move(to: CGPoint(x: x0, y: y0)); ctx.addLine(to: CGPoint(x: x0 + cos(a) * len, y: y0 + sin(a) * len)); ctx.strokePath()
        }
    }
}
