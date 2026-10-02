import AppKit

// Ecology check (tools/perch.sh ecology): the tank as a living place (Phase 6).
//
//   • sky: what is open to the sky — under a table, a house, a bark cave
//     covered; the open floor, the top of the table, open;
//   • sites: what draws what — each kind of feature tips the odds toward
//     its creatures, never so far that nothing else can come, and nothing
//     is certain; night, rain, cold shift them too;
//   • arrive: where they come in — a beetle out from under the bark, a worm
//     from the litter, a fly down onto the flowers, ants in a little line;
//   • prey: what they do there — a fly lands on the flowers, a moth goes
//     round a light after dark and rests up high by day, a mosquito hangs
//     over the water, a beetle frightened makes for the bark and lies low, an
//     ant finds the remains of a meal and carries them off, anything caught
//     in a downpour gets in under something, a beetle walks on over a rock;
//   • drops: rain beads on the leaves open to it (none under a roof), and
//     dries off after — quicker in the sun;
//   • chain: rain rolls in; it feels it getting worse, picks the shelter it
//     knows (built first), goes, waits it out, stays a while after (the shy
//     the longer), comes out, finds a drop on a leaf, has a look, drinks it,
//     and gets on with its life;
//   • sun: stone warms through in the sun; it basks on it, and later gets
//     into the shade;
//   • wind: in a gale it keeps off what sways, and gets down off it;
//   • hunt: a beetle lying low under bark is turned out; places where prey
//     comes are where it lies in wait; full up, it lets what wanders in be;
//   • mild: a mild weather, and the bold and curious go up to watch it;
//   • life: a long life in a whole tank, the weather changing, creatures
//     coming and going: never on nothing, never stuck, and all of it seen.
//
// PC_PART=sky,sites,arrive,prey,drops,chain,sun,wind,hunt,mild,life  PC_SEEDS (4)  PC_TRACE=1  PC_WHO  PC_LIFE (2400)

#if SHAPED
private let G = HabitatLayout.ground
private let scale: CGFloat = 0.78
private let standoff = 22 * scale
private let presets: [String: Personality] = Dictionary(uniqueKeysWithValues: Personality.presets.map { ($0.name, $0.p) })
private func who(_ names: [String]) -> [(String, Personality)] {
    let wanted = env["PC_WHO"].map { Set($0.split(separator: ",").map(String.init)) }
    return (["Default"] + names).filter { wanted?.contains($0) ?? true }.map { ($0, $0 == "Default" ? Personality() : presets[$0]!) }
}
private var seeds: Int { Int(env["PC_SEEDS"] ?? "4") ?? 4 }
private var tracing: Bool { env["PC_TRACE"] != nil }

/// Puts a thing in, exactly where asked.
@discardableResult
private func put(_ kind: HabitatItemKind, x: CGFloat, y: CGFloat = 0, w: CGFloat? = nil, h: CGFloat? = nil, _ hab: inout Habitat) -> HabitatItem {
    var it = hab.add(kind, at: CGPoint(x: x, y: y))
    if let w { it.w = w }
    if let h { it.h = h }
    it.x = x
    it.y = y
    it.flipped = false
    it.seed = 300 + it.id * 17
    Habitat.clamp(&it, in: hab.size)
    hab.items[hab.items.count - 1] = it
    return it
}

private func tank(_ width: CGFloat = 2400) -> Habitat { Habitat(biome: .forest, world: CGSize(width: width, height: 700)) }

/// The tank alive, laid out.
private func alive(_ h: Habitat, map: SurfaceMap, night: Bool = false) -> HabitatEcology {
    let e = HabitatEcology()
    e.night = night
    e.relayout(h, map: map)
    return e
}

/// A spider in `h` that knows everything in it, on the floor at `x`, with
/// the tank alive.
private func settle(_ h: Habitat, personality: Personality, at x: CGFloat, night: Bool = false) -> (SurfaceMap, Spider, HabitatEcology) {
    let desk = SurfaceMap()
    desk.standoff = standoff
    desk.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 25, windows: [])
    let m = surfaces(h, standoff: standoff)
    let s = Spider(map: desk)
    s.config.followCursor = false
    s.config.approachCursor = false
    s.config.scale = scale
    var d = s.design
    d.personality = personality
    s.apply(design: d)
    s.knowledge = HabitatKnowledge()
    for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
    s.enter(map: m, at: V2(x, G + 30), habitat: true)
    let e = alive(h, map: m, night: night)
    s.ecology = e
    s.tankRebuilt(h, smooth: false, inIt: true)
    // (It ate before it went in: ten minutes or so before it is hungry.)
    s.debugFed = 1
    return (m, s, e)
}

/// Runs the spider (and the tank's weather on its things) for `secs`, the
/// weather each second given by `weather` (nil: as it is); `each` false stops.
private func live(_ s: Spider, _ e: HabitatEcology, _ secs: CGFloat, weather: ((CGFloat) -> WeatherFeel)? = nil, each: ((CGFloat) -> Bool)? = nil) {
    var t: CGFloat = 0
    for _ in 0..<Int(secs / dt) {
        if let weather {
            let w = weather(t)
            if s.weather != w { s.weather = w }
        }
        e.update(s.weather, dt: dt)
        s.setCursor(V2(-4000, -4000))
        s.update(dt: dt)
        t += dt
        if let each, !each(t) { return }
    }
}

private func gap(_ r: CGRect, _ p: V2) -> CGFloat {
    V2(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY)).length
}

private func footed(_ s: Spider, _ m: SurfaceMap) -> Bool {
    guard let a = s.standingOn, let p = m.worldPoint(a) else { return false }
    return p.distance(to: s.worldPos) < 16
}

private func share(_ odds: [(kind: PreyKind, weight: CGFloat)], _ k: PreyKind) -> CGFloat {
    let total = odds.reduce(0) { $0 + $1.weight }
    return (odds.first { $0.kind == k }?.weight ?? 0) / max(total, 1e-9)
}

private func f(_ x: CGFloat?, _ fmt: String = "%.1f") -> String { x.map { String(format: fmt, Double($0)) } ?? "-" }

// MARK: Sky

private func skyCheck(_ b: inout Builder) {
    print("== sky: what is open to it")
    var h = tank()
    let table = put(.table, x: 600, &h)
    let cave = put(.barkCave, x: 1100, &h)
    let canopy = put(.leafCanopy, x: 1500, &h)
    // A room: walls and floorboards over them.
    _ = put(.wall, x: 1850, &h)
    _ = put(.wall, x: 2150, &h)
    let boards = put(.floorboards, x: 2000, y: 150, w: 340, &h)
    let sky = SkyCover(h)
    let floor = G + 2
    b.check("under the table: covered", sky.roof(over: V2(table.rect.midX, floor)) != nil, "\(table.rect)")
    b.check("the top of the table: open", sky.open(at: V2(table.rect.midX, table.rect.maxY + 2)) == 1)
    b.check("open floor: open", sky.open(at: V2(900, floor)) == 1 && sky.open(at: V2(1300, floor)) == 1)
    b.check("in the bark cave: covered", sky.roof(over: V2(cave.rect.midX, floor + 8)) != nil)
    b.check("under the leaf canopy: covered", sky.roof(over: V2(canopy.rect.midX, floor)) != nil)
    b.check("in the room under the floorboards: covered", sky.roof(over: V2(2000, floor))?.owner == boards.id)
    let spans = sky.covered(at: floor, minWidth: 10)
    print("  covered along the floor: " + spans.map { String(format: "%.0f–%.0f (#%d)", Double($0.lo), Double($0.hi), $0.owner) }.joined(separator: ", "))
    b.check("the floor's covered stretches include the table's", spans.contains { $0.lo < table.rect.midX && $0.hi > table.rect.midX })
    // A whole tank, quickly.
    let big = Habitat.preset(.forestFloor, world: world)
    let t0 = Date()
    let bigSky = SkyCover(big)
    let ms = Date().timeIntervalSince(t0) * 1000
    let bm = surfaces(big, standoff: standoff)
    let t1 = Date()
    let eco = alive(big, map: bm)
    let ms2 = Date().timeIntervalSince(t1) * 1000
    print(String(format: "  forest floor: sky %.0f ms (%d columns), whole ecology %.0f ms — %@", ms, bigSky.cols.count, ms2, eco.debugSummary))
    b.check("a whole tank's sky and ecology laid out quickly", ms < 60 && ms2 < 250, String(format: "%.0f + %.0f ms", ms, ms2))
}

// MARK: Sites

/// A tank with just one sort of thing in it (and a rock).
private func themed(_ theme: String) -> Habitat {
    var h = tank()
    put(.rock, x: 300, &h)
    switch theme {
    case "flowers":
        put(.floweringPlant, x: 900, &h); put(.floweringPlant, x: 1300, &h); put(.tinyFlowers, x: 1600, &h)
    case "water":
        put(.waterDish, x: 900, &h); put(.puddle, x: 1400, &h)
    case "litter":
        put(.leafPile, x: 900, &h); put(.leafHeap, x: 1300, &h); put(.pineNeedles, x: 1700, &h)
    case "bark":
        put(.log, x: 900, &h); put(.corkBark, x: 1300, &h); put(.barkCave, x: 1700, &h)
    case "plants":
        put(.broadLeaf, x: 900, &h); put(.largeFern, x: 1300, &h); put(.climbingVine, x: 1700, &h)
    case "dark":
        put(.rockCrevice, x: 900, &h); put(.logDen, x: 1400, &h)
    case "damp":
        put(.mossCushion, x: 900, &h); put(.moistMoss, x: 1300, &h)
    case "lights":
        put(.floorLamp, x: 900, &h); put(.lantern, x: 1400, y: 700, &h)
    default:
        break
    }
    return h
}

private func sitesCheck(_ b: inout Builder) {
    print("== sites: what draws what")
    func odds(_ theme: String, night: Bool = false, weather: WeatherFeel = .calm, sinceRain: CGFloat? = nil) -> (HabitatEcology, [(kind: PreyKind, weight: CGFloat)]) {
        let h = themed(theme)
        let e = alive(h, map: surfaces(h, standoff: standoff), night: night)
        e.update(weather, dt: 0.01)
        if let sinceRain { e.debugSinceRain(sinceRain) }
        return (e, e.arrivalOdds())
    }
    let (_, bare) = odds("bare")
    func line(_ name: String, _ o: [(kind: PreyKind, weight: CGFloat)]) {
        print("  \(name.padding(toLength: 16, withPad: " ", startingAt: 0)) " + o.map { "\($0.kind) " + String(format: "%.0f%%", Double(share(o, $0.kind) * 100)) }.joined(separator: "  "))
    }
    line("bare", bare)
    var all: [(String, [(kind: PreyKind, weight: CGFloat)])] = []
    /// How often, give or take, the tank's odds bring one a minute.
    func gapOf(_ e: HabitatEcology) -> CGFloat { (0..<120).map { _ in e.arrivalGap() }.reduce(0, +) / 120 }
    let (bareE, _) = odds("bare")
    let bareGap = gapOf(bareE)
    let (nightE, _) = odds("bare", night: true)
    let nightGap = gapOf(nightE)
    func expect(_ theme: String, _ kinds: [PreyKind], by: CGFloat = 2, night: Bool = false, base: [(kind: PreyKind, weight: CGFloat)]? = nil) {
        let (e, o) = odds(theme, night: night)
        line(theme + (night ? " (night)" : ""), o)
        all.append((theme, o))
        let ref = base ?? bare
        let g = gapOf(e), g0 = night ? nightGap : bareGap
        // Likelier to be what comes next, and more of them in an hour.
        let up = kinds.map { share(o, $0) / max(share(ref, $0), 1e-9) }
        let hourly = kinds.map { share(o, $0) / g / max(share(ref, $0) / g0, 1e-9) }
        b.check("\(theme)\(night ? " at night" : ""): more \(kinds.map { "\($0)" }.joined(separator: ", "))", up.allSatisfy { $0 >= 1.15 } && hourly.allSatisfy { $0 >= by },
                zip(up, hourly).map { String(format: "×%.1f of what comes, ×%.1f an hour", Double($0.0), Double($0.1)) }.joined(separator: "; ")
                + " — " + e.debugSummary.components(separatedBy: ",").first!)
    }
    expect("flowers", [.fruitFly, .moth])
    expect("water", [.mosquito], by: 2)
    expect("litter", [.beetle, .worm, .ant])
    expect("bark", [.beetle, .ant])
    expect("plants", [.ladybug])
    expect("dark", [.cricket])
    expect("damp", [.worm], by: 2)
    let (_, dark) = odds("bare", night: true)
    line("bare (night)", dark)
    expect("lights", [.moth], by: 1.6, night: true, base: dark)
    let (_, raining) = odds("litter", weather: WeatherFeel(rain: 0.8))
    let (_, dryLitter) = odds("litter")
    line("litter (rain)", raining)
    b.check("rain: more worms, fewer fliers", share(raining, .worm) > share(dryLitter, .worm) * 1.8 && share(raining, .fruitFly) < share(dryLitter, .fruitFly))
    let (_, cold) = odds("flowers", weather: WeatherFeel(snow: 0.6, cold: 0.9))
    let (eFl, warm) = odds("flowers")
    b.check("cold and snow: much less comes", cold.reduce(0) { $0 + $1.weight } < warm.reduce(0) { $0 + $1.weight } * 0.5)
    // Odds, never certainty: every kind can still come everywhere (bar a
    // ladybug after dark), and nothing takes most of it.
    let spread = all.allSatisfy { o in o.1.allSatisfy { $0.weight > 0 } && o.1.allSatisfy { share(o.1, $0.kind) < 0.6 } }
    b.check("nothing certain: all kinds possible in every tank, none more than 60%", spread)
    // Arrivals drawn: flies mostly, not only; to the flowers mostly.
    var kinds: [PreyKind: Int] = [:], atFlowers = 0, flies = 0
    let hF = themed("flowers")
    let flowerRects = hF.items.filter { $0.kind.definition.group == .flowering }.map { $0.rect.insetBy(dx: -40, dy: -40) }
    for _ in 0..<2000 {
        guard let a = eFl.arrival(near: V2(1200, G + 200)) else { continue }
        kinds[a.kind, default: 0] += 1
        if a.kind == .fruitFly {
            flies += 1
            if let l = a.land, flowerRects.contains(where: { $0.contains(l.point.point) }) { atFlowers += 1 }
        }
    }
    print("  2000 arrivals in the flower tank: " + kinds.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    b.check("flowers: flies the likeliest, but only likelier", (kinds[.fruitFly] ?? 0) == kinds.values.max() && (kinds[.fruitFly] ?? 0) < 1300 && kinds.count >= 6,
            "\(kinds[.fruitFly] ?? 0)/2000, \(kinds.count) kinds")
    b.check("…and the flies mostly come down on the flowers", CGFloat(atFlowers) > CGFloat(flies) * 0.6, "\(atFlowers)/\(flies)")
    let gapBare = (0..<200).map { _ in odds("bare").0.arrivalGap() }.reduce(0, +) / 200
    let rich = Habitat.preset(.forestFloor, world: world)
    let eRich = alive(rich, map: surfaces(rich, standoff: standoff))
    let gapRich = (0..<200).map { _ in eRich.arrivalGap() }.reduce(0, +) / 200
    print(String(format: "  between arrivals: a bare tank %.0f s, the forest floor %.0f s", Double(gapBare), Double(gapRich)))
    b.check("a lush tank is livelier than a bare one", gapRich < gapBare * 0.6 && gapRich > 90, String(format: "%.0f vs %.0f s", Double(gapRich), Double(gapBare)))
}

// MARK: Arrive

private func arriveCheck(_ b: inout Builder) {
    print("== arrive: where they come in")
    func check(_ theme: String, _ kind: PreyKind, _ label: String, _ ok: (EcoArrival, Habitat, HabitatEcology) -> Bool, want: CGFloat = 0.7) {
        let h = themed(theme)
        let e = alive(h, map: surfaces(h, standoff: standoff))
        var n = 0, good = 0
        var shown = 0
        for _ in 0..<200 {
            guard let a = e.arrival(near: V2(1200, G + 150), kind: kind) else { continue }
            n += 1
            if ok(a, h, e) { good += 1 } else if tracing, shown < 6 {
                shown += 1
                let it = h.items.min { gap($0.rect, a.at) < gap($1.rect, a.at) }!
                print(String(format: "    miss: %@ at (%.0f,%.0f) open %.2f feature %@, nearest %@ %.0f off", "\(kind)", Double(a.at.x), Double(a.at.y),
                             Double(e.open(at: a.at)), a.feature?.rawValue ?? "none", it.kind.rawValue, Double(gap(it.rect, a.at))))
            }
        }
        b.check(label, n > 150 && CGFloat(good) >= CGFloat(n) * want, "\(good)/\(n)")
    }
    func near(_ h: Habitat, _ p: V2, where f: (HabitatItem) -> Bool, _ d: CGFloat) -> Bool { h.items.contains { f($0) && gap($0.rect, p) < d } }
    check("bark", .beetle, "a beetle comes out from under the bark, low down by it", { a, h, _ in
        a.anchor != nil && near(h, a.at, where: { $0.kind.definition.traits.material == .bark || $0.kind.definition.group == .bark }, 60) && a.at.y < G + 60
    }, want: 0.8)
    check("litter", .worm, "a worm comes up out of the litter", { a, h, _ in
        near(h, a.at, where: { $0.kind.definition.shelf == .ground || $0.kind.definition.group == .leaves }, 50)
    }, want: 0.8)
    check("flowers", .fruitFly, "a fly comes down onto the flowers", { a, h, _ in
        guard let l = a.land else { return false }
        return near(h, l.point, where: { $0.kind.definition.group == .flowering }, 30) && a.at.y > l.point.y + 80
    })
    check("water", .mosquito, "a mosquito comes to the water", { a, h, _ in near(h, a.at, where: { $0.kind.nature[.drinkable] > 0 }, 300) })
    check("dark", .cricket, "a cricket comes out of the dark", { a, h, e in a.feature == .dark && e.open(at: a.at) < 0.5 }, want: 0.6)
    check("litter", .ant, "ants come in a little line", { a, _, _ in a.count >= 2 && a.anchor != nil })
    check("plants", .ladybug, "a ladybug turns up on a plant", { a, h, _ in near(h, a.at, where: { $0.kind.definition.shelf == .plants }, 20) })
}

// MARK: Prey

/// A creature loose in `h`, the spider far off, for `secs`; `each` sees it
/// every frame (false: stop).
private func loose(_ kind: PreyKind, in h: Habitat, at p: V2, secs: CGFloat, night: Bool = false, eco on: Bool = true,
                   weather: ((CGFloat) -> WeatherFeel)? = nil, spider sp: ((CGFloat) -> V2)? = nil, setup: ((Prey, SurfaceMap, HabitatEcology) -> Void)? = nil,
                   each: (Prey, CGFloat) -> Bool) -> Prey {
    let m = surfaces(h, standoff: standoff)
    let e = alive(h, map: m, night: night)
    let c = Prey(kind: kind, id: 1, at: p, scale: scale)
    c.eco = on ? e : nil
    c.home = CGRect(x: p.x - 450, y: G + 10, width: 900, height: 560)
    if !kind.flies, let s = m.nearestSpot(to: p, within: 80) {
        c.emerge(on: s.anchor, dir: 1, map: m)
        c.den = s.anchor
    }
    c.alpha = 1
    setup?(c, m, e)
    var t: CGFloat = 0
    for _ in 0..<Int(secs / dt) {
        let w = weather?(t) ?? .calm
        e.update(w, dt: dt)
        c.update(dt: dt, t: t, map: m, spider: sp?(t) ?? V2(-3000, G + 30), spiderLoop: nil, cursor: nil)
        t += dt
        if !each(c, t) { break }
    }
    return c
}

private func preyCheck(_ b: inout Builder) {
    print("== prey: at home in the tank")
    // A fly: down on the flowers.
    do {
        var h = tank()
        let fl = put(.floweringPlant, x: 1000, &h)
        put(.boulder, x: 1450, &h)
        put(.log, x: 700, &h)
        for on in [true, false] {
            var landings = 0, onFlower = 0, wasOn = false
            for sd in 0..<seeds {
                reseed(UInt64(4000 + sd))
                _ = loose(.fruitFly, in: h, at: V2(1150, G + 260), secs: 240, eco: on) { p, _ in
                    if p.onSurface, !wasOn {
                        landings += 1
                        if gap(fl.rect, p.pos) < 16 { onFlower += 1 }
                    }
                    wasOn = p.onSurface
                    return true
                }
            }
            print(String(format: "  fly %@: %d landings, %d on the flowers", on ? "in the tank" : "(as on the desktop)", landings, onFlower))
            if on { b.check("a fly lands on the flowers, mostly", landings > 10 && CGFloat(onFlower) > CGFloat(landings) * 0.5, "\(onFlower)/\(landings)") }
        }
    }
    // A moth: round a light after dark; up high on a plant by day.
    do {
        var h = tank()
        let lamp = put(.floorLamp, x: 1100, &h)
        put(.largeFern, x: 1500, &h)
        put(.broadLeaf, x: 800, &h)
        var near = 0, frames = 0
        for sd in 0..<seeds {
            reseed(UInt64(4100 + sd))
            _ = loose(.moth, in: h, at: V2(900, G + 300), secs: 90, night: true) { p, _ in
                frames += 1
                if p.pos.distance(to: V2(lamp.rect.midX, lamp.rect.minY + lamp.rect.height * 0.8)) < 90 { near += 1 }
                return true
            }
        }
        b.check("after dark, a moth goes round the light", CGFloat(near) > CGFloat(frames) * 0.3, String(format: "%.0f%% of the time", Double(near) / Double(frames) * 100))
        // A lantern hung high from the lid, flowers down below it: a moth by
        // the flowers after dark still finds its way up to the light.
        var hl = tank()
        put(.floweringPlant, x: 1100, &hl)
        let lantern = put(.lantern, x: 1100, y: 700, &hl)
        let lightAt = V2(lantern.rect.midX, lantern.rect.minY + lantern.rect.height * 0.25)
        var up = 0
        for sd in 0..<seeds {
            reseed(UInt64(4150 + sd))
            var close: CGFloat = 0
            _ = loose(.moth, in: hl, at: V2(1150, G + 180), secs: 90, night: true) { p, _ in
                if p.pos.distance(to: lightAt) < 110 { close += dt }
                return close < 8
            }
            if close >= 8 { up += 1 }
        }
        b.check("after dark, a moth down by the flowers finds its way up to a lantern hung high", up >= seeds - 1, "\(up)/\(seeds) (light at \(Int(lightAt.y)))")
        // By day: up on the plants, mostly — high.
        let plants = h.items.filter { $0.kind.definition.shelf == .plants }.map { $0.rect.insetBy(dx: -12, dy: -12) }
        var rests = [0, 0], onPlants = [0, 0], height: [CGFloat] = [0, 0]
        for (i, on) in [true, false].enumerated() {
            for sd in 0..<seeds {
                reseed(UInt64(4200 + sd))
                var wasOn = false
                _ = loose(.moth, in: h, at: V2(1200, G + 250), secs: 300, eco: on) { p, _ in
                    if p.onSurface, !wasOn {
                        rests[i] += 1
                        height[i] += p.pos.y - G
                        if plants.contains(where: { $0.contains(p.pos.point) }) { onPlants[i] += 1 }
                    }
                    wasOn = p.onSurface
                    return true
                }
            }
        }
        func pct(_ i: Int) -> CGFloat { CGFloat(onPlants[i]) / CGFloat(max(rests[i], 1)) }
        b.check("by day, a moth rests up on the plants, mostly", rests[0] > 8 && pct(0) > 0.55 && pct(0) > pct(1) + 0.2,
                String(format: "%.0f%% of %d rests on plants, %.0f pt up (vs %.0f%%, %.0f pt, as on the desktop)", Double(pct(0) * 100), rests[0],
                       Double(height[0] / CGFloat(max(rests[0], 1))), Double(pct(1) * 100), Double(height[1] / CGFloat(max(rests[1], 1)))))
    }
    // A mosquito: over the water.
    do {
        var h = tank()
        let dish = put(.waterDish, x: 1200, &h)
        put(.broadLeaf, x: 800, &h)
        var near = 0, frames = 0, baseNear = 0
        for on in [true, false] {
            for sd in 0..<seeds {
                reseed(UInt64(4300 + sd))
                _ = loose(.mosquito, in: h, at: V2(900, G + 250), secs: 120, eco: on) { p, _ in
                    if on { frames += 1 }
                    if gap(dish.rect.insetBy(dx: 0, dy: -40), p.pos) < 70 { if on { near += 1 } else { baseNear += 1 } }
                    return true
                }
            }
        }
        b.check("a mosquito hangs about the water", CGFloat(near) > CGFloat(frames) * 0.3 && near > baseNear * 2,
                String(format: "%.0f%% of the time (vs %.0f%%)", Double(near) / Double(frames) * 100, Double(baseNear) / Double(frames) * 100))
    }
    // A beetle, rushed: under the bark, and lying low.
    do {
        var h = tank()
        let bark = put(.corkBark, x: 1000, &h)
        put(.log, x: 1400, &h)
        var hid = 0, underBark = 0
        for sd in 0..<seeds {
            reseed(UInt64(4400 + sd))
            var done = false
            _ = loose(.beetle, in: h, at: V2(1150, G + 10), secs: 30, spider: { t in
                // Something big coming at it, fast, from the right.
                V2(1400 - min(t, 3) * 70, G + standoff)
            }) { p, t in
                if p.hidden, !done {
                    done = true
                    hid += 1
                    if gap(bark.rect, p.pos) < 40 { underBark += 1 }
                    if tracing { print(String(format: "    hid at %.1fs (%.0f,%.0f) cover %.2f", Double(t), Double(p.pos.x), Double(p.pos.y), Double(p.cover))) }
                }
                return true
            }
        }
        b.check("a beetle rushed makes for the bark and lies low", hid >= seeds - 1 && underBark >= hid - 1, "\(hid)/\(seeds), by the bark \(underBark)")
    }
    // An ant: finds the remains of a meal, has a nose round, carries them off.
    do {
        var h = tank()
        put(.log, x: 700, &h)
        var carried = 0, gone = 0
        for sd in 0..<seeds {
            reseed(UInt64(4500 + sd))
            var rid = 0, took = false
            let a = loose(.ant, in: h, at: V2(1500, G + 10), secs: 200, setup: { p, _, e in
                e.leaveRemains(of: .cricket, at: V2(1150, G), angle: 0)
                rid = e.remains.last!.id
                p.leaveAge = 400
            }) { p, _ in
                if p.carrying == rid { took = true; p.leaveAge = min(p.leaveAge, p.age + 10) }
                return !p.gone
            }
            if took { carried += 1 }
            if a.gone { gone += 1 }
        }
        b.check("an ant finds the remains of a meal and carries them off", carried >= seeds - 1 && gone >= carried - 1, "carried \(carried)/\(seeds), away with it \(gone)")
    }
    // A downpour: in under the table.
    do {
        var h = tank()
        let table = put(.table, x: 1000, &h)
        for kind in [PreyKind.cricket, .beetle, .worm, .fruitFly] {
            var under = 0
            for sd in 0..<seeds {
                reseed(UInt64(4600 + sd + kind.rawValue * 10))
                var dry: CGFloat = 0
                var lastLine = ""
                _ = loose(kind, in: h, at: V2(table.rect.maxX + 110, G + (kind.flies ? 160 : 10)), secs: 50, weather: { _ in WeatherFeel(rain: 0.9) }) { p, t in
                        let inUnder = gap(table.rect.insetBy(dx: 10, dy: 0), p.pos) < 1 && p.onSurface
                    dry = inUnder ? dry + dt : 0
                    if tracing {
                        let l = String(format: "(%.0f,%.0f) %@ %@", Double(p.pos.x), Double(p.pos.y), p.onSurface ? "on" : "air", p.debugTank)
                        if l != lastLine, Int(t * 60) % 30 == 0 { print(String(format: "      %@ %5.1f %@", kind.label, Double(t), l)); lastLine = l }
                    }
                    return dry < 5
                }
                if dry >= 5 { under += 1 }
            }
            b.check("in a downpour, a \(kind.label.lowercased()) gets in under the table", under >= seeds - 1, "\(under)/\(seeds)")
        }
    }
    // Over a rock, not stuck at it.
    do {
        var h = tank()
        let rock = put(.boulder, x: 1100, &h)
        for on in [true, false] {
            var over = 0
            for sd in 0..<seeds {
                reseed(UInt64(4700 + sd))
                var lo = CGFloat.greatestFiniteMagnitude, hi: CGFloat = 0, top: CGFloat = 0
                _ = loose(.beetle, in: h, at: V2(rock.rect.minX - 60, G + 10), secs: 200, eco: on) { p, _ in
                    lo = min(lo, p.pos.x); hi = max(hi, p.pos.x); top = max(top, p.pos.y)
                    return true
                }
                if hi > rock.rect.maxX + 10 || top > rock.rect.maxY - 12 { over += 1 }
                if tracing { print(String(format: "    beetle %@: x %.0f…%.0f, up to %.0f (rock %.0f…%.0f, top %.0f)", on ? "tank" : "desk", Double(lo), Double(hi), Double(top), Double(rock.rect.minX), Double(rock.rect.maxX), Double(rock.rect.maxY))) }
            }
            if on { b.check("a beetle walks up and over a boulder", over >= seeds - 1, "\(over)/\(seeds)") } else { print("  (as on the desktop: over it \(over)/\(seeds))") }
        }
    }
}

// MARK: Drops

private func dropsCheck(_ b: inout Builder) {
    print("== drops: rain on the leaves")
    var h = tank()
    put(.broadLeaf, x: 700, &h)
    put(.largeFern, x: 1150, &h)
    let canopy = put(.leafCanopy, x: 1650, &h)
    put(.smallFern, x: 1650, &h)
    let m = surfaces(h, standoff: standoff)
    let e = alive(h, map: m)
    print("  " + e.debugSummary)
    for _ in 0..<Int(60 / dt) { e.update(WeatherFeel(rain: 0.8), dt: dt) }
    let wet = e.droplets
    let underCanopy = wet.filter { gap(canopy.rect, $0.p) < 1 && $0.p.y < canopy.rect.minY + canopy.rect.height * 0.5 }
    print(String(format: "  after a minute's rain: %d drops, %d reachable, sizes %.1f–%.1f", wet.count, wet.filter(\.reachable).count,
                 Double(wet.map(\.r).min() ?? 0), Double(wet.map(\.r).max() ?? 0)))
    b.check("rain beads on the leaves", wet.count >= 12 && wet.contains(where: \.reachable), "\(wet.count)")
    b.check("…only where open to it", wet.allSatisfy { e.open(at: $0.p + V2(0, 3)) > 0.5 } && underCanopy.isEmpty, "\(underCanopy.count) under the canopy")
    // Drying off: in the sun, soon; on a still grey day, a good while.
    func dryIn(_ w: WeatherFeel) -> CGFloat {
        let e2 = alive(h, map: m)
        for _ in 0..<Int(60 / dt) { e2.update(WeatherFeel(rain: 0.8), dt: dt) }
        var t: CGFloat = 0
        while !e2.droplets.isEmpty, t < 1200 { e2.update(w, dt: 0.1); t += 0.1 }
        return t
    }
    let sun = dryIn(WeatherFeel(sun: 1, heat: 0.8)), grey = dryIn(.calm), wind = dryIn(WeatherFeel(wind: 1, gust: 0.8))
    print(String(format: "  all dried off: in the sun %.0f s, on a still day %.0f s, in a gale %.0f s", Double(sun), Double(grey), Double(wind)))
    b.check("drops dry off after, quicker in the sun and the wind", sun < grey * 0.5 && wind < grey && grey > 180 && sun > 20)
    // A fog leaves a dew; a freeze, none.
    let e3 = alive(h, map: m)
    for _ in 0..<Int(90 / dt) { e3.update(WeatherFeel(fog: 1, cold: 0.25), dt: dt) }
    let e4 = alive(h, map: m)
    for _ in 0..<Int(90 / dt) { e4.update(WeatherFeel(snow: 0.7, cold: 0.9), dt: dt) }
    b.check("a fog leaves a dew; in snow none", e3.droplets.count >= 4 && e4.droplets.isEmpty, "fog \(e3.droplets.count), snow \(e4.droplets.count)")
    // In the made tanks: the drops it could drink, somewhere it could walk
    // to from the floor (over what meets what).
    var fewest = Int.max, fewestIn = ""
    for p in Habitat.Preset.allCases where p != .empty {
        let hp = Habitat.preset(p, world: world)
        let mp = surfaces(hp, standoff: standoff)
        let ep = alive(hp, map: mp)
        for _ in 0..<Int(60 / dt) { ep.update(WeatherFeel(rain: 0.8), dt: dt) }
        // (How many steps over from the floor: the way-finding looks six deep.)
        var depth: [String: Int] = ["screen:0": 0], frontier = ["screen:0"]
        let out = Dictionary(grouping: mp.junctions, by: \.from)
        while !frontier.isEmpty {
            var next: [String] = []
            for l in frontier { for j in out[l] ?? [] where depth[j.to] == nil { depth[j.to] = depth[l]! + 1; next.append(j.to) } }
            frontier = next
        }
        let can = ep.droplets.filter(\.reachable)
        let stand = can.compactMap { d in ep.spot(near: d.p + V2(0, standoff), within: 34 * scale).map { (d, $0) } }
        let walk = stand.filter { (depth[$0.1.anchor.loopID] ?? 99) <= 6 }
        print(String(format: "  %@: %d drops, %d on what it can stand on, %d it could stand by, %d of those within six steps of the floor (deepest %d)", p.rawValue,
                     ep.droplets.count, can.count, stand.count, walk.count, stand.map { depth[$0.1.anchor.loopID] ?? 99 }.max() ?? 0))
        if walk.count < fewest { fewest = walk.count; fewestIn = p.rawValue }
    }
    b.check("in every made tank, rain it could walk over to and drink", fewest >= 6, "fewest \(fewest), \(fewestIn)")
}

// MARK: Chain

/// A tank with a table (built shelter) and plants round it, a rock, a cave.
private func chainTank() -> (Habitat, table: HabitatItem) {
    var h = tank(2600)
    put(.rock, x: 300, &h)
    let table = put(.table, x: 900, &h)
    put(.broadLeaf, x: 1180, &h)
    put(.largeFern, x: 1500, &h)
    return (h, table)
}

private func chainCheck(_ b: inout Builder) {
    print("== chain: rain, shelter, out again, a drop, and on")
    var waited: [String: [CGFloat]] = [:], setOff: [String: [CGFloat]] = [:]
    for (name, p) in who(["Shy", "Show-off", "Curious", "Lazy"]) {
        var full = 0, rows: [String] = []
        for sd in 0..<seeds {
            reseed(UInt64(5000 + sd))
            let (h, table) = chainTank()
            let (m, s, e) = settle(h, personality: p, at: 1650)
            s.debugSetUrges(thirst: 0.35, view: 0, rest: 0, roam: 0)
            live(s, e, 3)
            // Rain rolls in over half a minute, pours for a minute and a
            // half, and clears over twenty seconds.
            let rollIn: CGFloat = 30, pours: CGFloat = 90, clears: CGFloat = 20
            func rain(_ t: CGFloat) -> CGFloat {
                if t < rollIn { return smoothstep(t / rollIn) * 0.8 }
                if t < rollIn + pours { return 0.8 }
                return max(0, 0.8 * (1 - smoothstep((t - rollIn - pours) / clears)))
            }
            let over = rollIn + pours + clears
            var stages: [String: CGFloat] = [:], rainAtSetOff: CGFloat?, sheltered: CGFloat = 0, pouring: CGFloat = 0
            var shelterPlace: HabitatPlace?, dropID: Int?, drankDrop = false, floating = 0, offFor = 0, lastLine = ""
            func mark(_ k: String, _ t: CGFloat) { if stages[k] == nil { stages[k] = t } }
            live(s, e, over + 180, weather: { t in WeatherFeel(rain: rain(t), cold: rain(t) * 0.2) }) { t in
                let k = s.debugErrandKind
                if tracing {
                    let l = "\(s.debugState) | \(s.debugErrand) \(s.debugErrandPlace.map { "\($0.anchor.loopID):\($0.anchor.segIdx)" } ?? "")\(s.sheltered ? " | sheltered" : "")"
                    if l != lastLine || (env["PC_TRACE"] == "2" && Int(t * 60) % 60 == 0) {
                        print(String(format: "      %6.1f rain %.2f (%.0f,%.0f) %@ | %@", Double(t), Double(rain(t)), Double(s.worldPos.x), Double(s.worldPos.y), l, s.debugEcology))
                        lastLine = l
                    }
                }
                if k == "shelter", stages["set off"] == nil {
                    mark("set off", t)
                    rainAtSetOff = rain(t)
                    shelterPlace = s.debugErrandPlace
                }
                if k == "shelter", s.debugErrand.contains(" act ") { mark("there", t) }
                if t > rollIn + 5, t < rollIn + pours {
                    pouring += dt
                    if s.sheltered { sheltered += dt }
                }
                if t > over, k == "emerge" { mark("out", t) }
                if let o = stages["out"], t > o, k == "dew", let id = s.debugDropID, id != dropID, !drankDrop {
                    mark("to a drop", t)
                    dropID = id
                }
                if let id = dropID, s.debugDrinking, let at = s.debugSipAt, let d = e.droplet(id: id), d.p.distance(to: at) < 3 {
                    mark("drinking", t)
                }
                if let id = dropID, stages["drinking"] != nil, e.droplet(id: id) == nil { drankDrop = true }
                if drankDrop, k == nil, stages["on"] == nil { mark("on", t) }
                offFor = s.isStanding && !footed(s, m) ? offFor + 1 : 0
                if offFor == 6 { floating += 1 }
                return stages["on"] == nil || t < stages["on"]! + 5
            }
            let built = shelterPlace.map { $0.q[.made] >= 0.5 || $0.roofOwner == table.id || $0.thing == table.id } ?? false
            let dryShare = pouring > 0 ? sheltered / pouring : 0
            // (Into the house, or whatever cover it thinks best: built first is
            // the places check's to hold it to.)
            let ok = stages["set off"] != nil && stages["there"] != nil && dryShare > 0.75 && stages["out"] != nil
                && stages["drinking"] != nil && drankDrop && stages["on"] != nil && floating == 0
            if ok { full += 1 }
            if let o = stages["out"] { waited[name, default: []].append(o - over) }
            if let r = rainAtSetOff { setOff[name, default: []].append(r) }
            let order = ["set off", "there", "out", "to a drop", "drinking", "on"]
            rows.append("     \(sd) " + order.map { "\($0) \(f(stages[$0], "%.0f"))" }.joined(separator: "  ")
                        + String(format: "  | rain %.2f at setting off, dry %.0f%% of the downpour, built %@%@", Double(rainAtSetOff ?? -1), Double(dryShare * 100),
                                 built ? "yes" : "no", floating > 0 ? " FLOATING \(floating)" : ""))
        }
        print("  \(name)")
        rows.forEach { print($0) }
        b.check("\(name): the whole chain, rain to a drop drunk and on with its life", full >= seeds - 1, "\(full)/\(seeds)")
    }
    func mean(_ x: [CGFloat]?) -> CGFloat { (x ?? []).reduce(0, +) / CGFloat(max(x?.count ?? 0, 1)) }
    if waited["Shy"] != nil, waited["Show-off"] != nil {
        print(String(format: "  stayed in after the rain: shy %.0f s, show-off %.0f s; set off at rain: shy %.2f, show-off %.2f",
                     Double(mean(waited["Shy"])), Double(mean(waited["Show-off"])), Double(mean(setOff["Shy"])), Double(mean(setOff["Show-off"]))))
        b.check("the shy one stays in longer after the rain", mean(waited["Shy"]) > mean(waited["Show-off"]) * 1.4)
        b.check("…and goes in sooner, as it gets worse", mean(setOff["Shy"]) < mean(setOff["Show-off"]))
    }
}

// MARK: Sun

private func sunCheck(_ b: inout Builder) {
    print("== sun: warm stone to bask on, then the shade")
    var basked = 0, shaded = 0, rows: [String] = []
    for sd in 0..<seeds {
        reseed(UInt64(6000 + sd))
        var h = tank()
        let stone = put(.baskingStone, x: 1100, &h)
        let table = put(.table, x: 1600, &h)
        put(.rock, x: 500, &h)
        let (_, s, e) = settle(h, personality: presets["Lazy"]!, at: 800)
        s.debugSetUrges(thirst: 0, view: 0, rest: 0, roam: 0)
        let sunny = WeatherFeel(sun: 1, heat: 0.7)
        var warmAt: CGFloat?, onStone: CGFloat?, inShade: CGFloat?, lastLine = ""
        live(s, e, 900, weather: { _ in sunny }) { t in
            if warmAt == nil, (e.warmth[stone.id] ?? 0) > 0.5 { warmAt = t }
            if tracing {
                let l = "\(s.debugState) | \(s.debugErrand)"
                if l != lastLine { print(String(format: "      %6.1f %@ sun %.0f", Double(t), l, Double(s.debugSunOn))); lastLine = l }
            }
            if onStone == nil, s.debugErrandKind == "bask", s.debugErrand.contains(" act "), let pl = s.debugErrandPlace,
               pl.owner == stone.id || gap(stone.rect, pl.point) < 30 { onStone = t }
            if onStone != nil, inShade == nil, s.debugErrandKind == "shade", s.debugErrand.contains(" act "), s.sheltered { inShade = t }
            return inShade == nil
        }
        _ = table
        if onStone != nil { basked += 1 }
        if inShade != nil { shaded += 1 }
        rows.append("     \(sd)  stone warm \(f(warmAt, "%.0f"))  basking on it \(f(onStone, "%.0f"))  into the shade \(f(inShade, "%.0f"))")
    }
    rows.forEach { print($0) }
    b.check("in the sun, it basks on the warm stone", basked >= seeds - 1, "\(basked)/\(seeds)")
    b.check("…and after long enough in it, gets into the shade", shaded >= seeds - 1, "\(shaded)/\(seeds)")
}

// MARK: Wind

private func windCheck(_ b: inout Builder) {
    print("== wind: steady things in a gale")
    var h = tank()
    let plant = put(.largeFern, x: 900, &h)
    let stump = put(.stump, x: 1400, &h)
    put(.rock, x: 1800, &h)
    // Where it would perch, calm and in a gale.
    var onPlant = [0, 0]
    for (i, w) in [WeatherFeel.calm, WeatherFeel(wind: 1.2, gust: 0.8)].enumerated() {
        for sd in 0..<40 {
            reseed(UInt64(6500 + sd))
            let (_, s, _) = settle(h, personality: Personality(), at: 1150)
            s.weather = w
            s.update(dt: dt)
            if let pl = s.debugChoose(.perch), pl.owner == plant.id { onPlant[i] += 1 }
        }
    }
    print("  a perch on the fern: calm \(onPlant[0])/40, in a gale \(onPlant[1])/40")
    b.check("in a gale, it doesn't pick a swaying plant to perch on", onPlant[1] < max(onPlant[0] / 2, 2), "\(onPlant[1]) vs \(onPlant[0])")
    // On the fern in a gale: off it.
    var off = 0
    for sd in 0..<seeds {
        reseed(UInt64(6600 + sd))
        let (m, s, e) = settle(h, personality: Personality(), at: 1150)
        let onIt = m.sampleSpots(spacing: 10).filter { m.owner(of: $0.anchor) == plant.id }
        guard let spot = onIt.filter({ $0.seg.facing == .up }).max(by: { $0.point.y < $1.point.y }) ?? onIt.max(by: { $0.point.y < $1.point.y }) else {
            print("  (nowhere on the fern to put it: \(onIt.count) spots)")
            continue
        }
        s.debugAttach(loopID: spot.anchor.loopID, segIdx: spot.anchor.segIdx, t: spot.anchor.t, dir: 1)
        live(s, e, 1)
        var gone: CGFloat?, steady: CGFloat = 0, startOwner = s.standingOn.flatMap { m.owner(of: $0) }, lastLine = ""
        live(s, e, 60, weather: { _ in WeatherFeel(wind: 1.3, gust: 0.9) }) { t in
            let owner = s.standingOn.flatMap { m.owner(of: $0) }
            let swaying = owner.flatMap { o in h.item(id: o) }?.kind.sways ?? false
            steady = s.isStanding && !swaying ? steady + dt : 0
            if tracing {
                let l = "\(s.debugState) | \(s.debugErrand) | on \(owner.map { "#\($0)" } ?? "tank")"
                if l != lastLine { print(String(format: "      %5.1f %@", Double(t), l)); lastLine = l }
            }
            if steady > 3 { gone = t; return false }
            return true
        }
        if gone != nil { off += 1 }
        print("  on the fern (#\(plant.id), started on \(startOwner.map { "#\($0)" } ?? "tank")) in a gale: off it, steady \(f(gone, "%.0fs"))  (\(s.debugErrand))")
    }
    _ = stump
    b.check("on a swaying plant in a gale, it gets off it", off >= seeds - 1, "\(off)/\(seeds)")
}

// MARK: Hunt

private func huntCheck(_ b: inout Builder) {
    print("== hunt: by where things are")
    // A beetle lying low under bark: turned out.
    var flushed = 0, caughtN = 0
    for sd in 0..<seeds {
        reseed(UInt64(7000 + sd))
        var h = tank()
        let bark = put(.corkBark, x: 1000, &h)
        put(.log, x: 1500, &h)
        let (m, s, e) = settle(h, personality: presets["Curious"]!, at: 1700)
        s.debugFed = 0.1
        s.debugSetUrges(thirst: 0, view: 0, rest: 0, roam: 0)
        // A beetle under the bark, lying low, seen going in.
        guard let spot = e.haunt(.hide, for: .beetle, near: V2(bark.rect.midX, G), within: 200) else { b.check("somewhere under the bark to hide", false); continue }
        let c = s.releaseInTank(EcoArrival(kind: .beetle, site: nil, feature: .bark, at: spot.point, anchor: spot.anchor, patch: h.items[0].rect)).first!
        c.alpha = 1
        c.noticed = true
        c.debugHide(until: 9999, map: m)
        var out: CGFloat?, got: CGFloat?, lastLine = ""
        live(s, e, 300) { t in
            if tracing {
                let l = "\(s.debugState) | \(s.debugErrand) | beetle \(c.hidden ? "hidden" : "out") \(c.state)"
                if l != lastLine { print(String(format: "      %6.1f %@", Double(t), l)); lastLine = l }
            }
            if out == nil, !c.hidden { out = t }
            if got == nil, c.state != .loose { got = t }
            return got == nil
        }
        if out != nil { flushed += 1 }
        if got != nil { caughtN += 1 }
        print("  beetle under the bark: turned out \(f(out, "%.0fs")), caught \(f(got, "%.0fs"))")
    }
    b.check("a beetle lying low under bark is found and turned out", flushed >= seeds - 1, "\(flushed)/\(seeds)")
    b.check("…and caught", caughtN >= seeds - 2, "\(caughtN)/\(seeds)")
    // Where it lies in wait: by the flowers and the water.
    var h = tank()
    let fl = put(.floweringPlant, x: 700, &h)
    let dish = put(.waterDish, x: 1700, &h)
    put(.rock, x: 1200, &h)
    var by = 0, n = 0
    for sd in 0..<40 {
        reseed(UInt64(7100 + sd))
        let (_, s, _) = settle(h, personality: Personality(), at: 1200)
        s.debugFed = 0.2
        guard let pl = s.debugChoose(.hunt) else { continue }
        n += 1
        if gap(fl.rect, pl.point) < 120 || gap(dish.rect, pl.point) < 120 { by += 1 }
    }
    b.check("it lies in wait where prey comes: by the flowers, the water", n > 30 && CGFloat(by) > CGFloat(n) * 0.7, "\(by)/\(n)")
    // Full up, what wanders in is let be (and watched).
    var letBe = 0
    for sd in 0..<seeds {
        reseed(UInt64(7200 + sd))
        let (_, s, e) = settle(tank(), personality: Personality(), at: 1200)
        s.debugFed = 0.97
        var hunted = false
        if let a = e.spot(near: V2(1350, G + standoff), within: 40) {
            let c = s.releaseInTank(EcoArrival(kind: .cricket, site: nil, feature: nil, at: a.point, anchor: a.anchor, patch: .null)).first!
            c.alpha = 1
            c.noticed = true
            live(s, e, 40, each: { _ in
                if s.debugHuntTarget == c.id { hunted = true }
                return !hunted
            })
        }
        if !hunted { letBe += 1 }
    }
    b.check("full up, it lets a creature that wandered in be", letBe >= seeds - 1, "\(letBe)/\(seeds)")
}

// MARK: Mild weather

private func mildCheck(_ b: inout Builder) {
    print("== mild: the bold and curious out watching the weather")
    var ups: [String: Int] = [:]
    for (name, p) in [("Shy", presets["Shy"]!), ("Curious", presets["Curious"]!), ("Show-off", presets["Show-off"]!)] {
        for sd in 0..<seeds {
            reseed(UInt64(7500 + sd))
            var h = tank()
            let look = put(.lookout, x: 1300, &h)
            put(.rock, x: 700, &h)
            let (_, s, e) = settle(h, personality: p, at: 900)
            s.debugSetUrges(thirst: 0, view: 0.2, rest: 0, roam: 0)
            var up = false
            live(s, e, 600, weather: { _ in WeatherFeel(wind: 0.3, gust: 0.3, rain: 0.1, fog: 0.4, cold: 0.2) }) { _ in
                if s.debugErrandKind == "lookout", s.debugUnderfoot == look.id, s.debugErrand.contains(" act ") { up = true; return false }
                return true
            }
            if up { ups[name, default: 0] += 1 }
        }
    }
    print("  up the lookout in a drizzly fog (of \(seeds)): " + ups.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    b.check("the bold and curious go up to watch it more than the shy", (ups["Curious"] ?? 0) + (ups["Show-off"] ?? 0) > (ups["Shy"] ?? 0) * 2 + 1
            && (ups["Curious"] ?? 0) + (ups["Show-off"] ?? 0) >= seeds)
}

// MARK: Life

private func lifeCheck(_ b: inout Builder) {
    let secs = CGFloat(Double(env["PC_LIFE"] ?? "2400") ?? 2400)
    print("== life: \(Int(secs / 60)) minutes in a whole tank, alive")
    for (name, p) in who(["Curious", "Shy"]) {
        reseed(UInt64(env["PC_LIFESEED"].flatMap(Int.init) ?? 8000))
        let h = Habitat.preset(.forestFloor, world: world)
        let (m, s, e) = settle(h, personality: p, at: world.width / 2)
        // The weather: a spell of each, round and round.
        let spells: [(CGFloat, WeatherFeel)] = [
            (240, .calm), (200, WeatherFeel(wind: 0.3, gust: 0.4, rain: 0.8, cold: 0.15, storm: 0.3)), (240, .calm),
            (240, WeatherFeel(sun: 1, heat: 0.7)), (180, WeatherFeel(wind: 1.1, gust: 0.9)), (200, WeatherFeel(fog: 0.9, cold: 0.25)),
            (180, WeatherFeel(snow: 0.7, cold: 0.8)),
        ]
        let cycle = spells.reduce(0) { $0 + $1.0 }
        func weather(_ t: CGFloat) -> WeatherFeel {
            var u = t.truncatingRemainder(dividingBy: cycle)
            for (d, w) in spells { if u < d { return w }; u -= d }
            return .calm
        }
        var kinds: [String: Int] = [:], last: String?, since: CGFloat = 0, longest: CGFloat = 0, floating = 0, offFor = 0
        var arrived: [PreyKind: Int] = [:], caughtN = 0, nextArrival = e.arrivalGap() * 0.5, lastCaught: Prey?
        var lastRemains = 0, remainsLeft = 0, carriedOff = Set<Int>(), hidAway = Set<Int>(), tookCover = Set<Int>()
        // Each downpour: in under something for it, and out again after.
        var wasRough = false, dryFor: CGFloat = 0, downpours = 0, shelteredSpells = 0, outAfter = 0, endedAt: CGFloat?, spellDry = false
        var recent: [String] = []
        var t: CGFloat = 0
        for _ in 0..<Int(secs / dt) {
            let w = weather(t)
            if s.weather != w { s.weather = w }
            e.night = Int(t / 600) % 3 == 2
            e.update(w, dt: dt)
            if Int(t / 600) % 2 == 0 { s.setCursor(V2(-4000, -4000)) }
            s.update(dt: dt)
            t += dt
            if t > nextArrival {
                nextArrival = t + e.arrivalGap()
                if s.prey.filter({ $0.state == .loose }).count < 4, let a = e.arrival(near: s.worldPos) {
                    for c in s.releaseInTank(a) { arrived[c.kind, default: 0] += 1 }
                }
            }
            if let c = s.prey.first(where: { $0.state == .caught }), c !== lastCaught { caughtN += 1; lastCaught = c }
            if w.rough {
                if !wasRough { downpours += 1; spellDry = false; dryFor = 0 }
                dryFor = s.sheltered ? dryFor + dt : 0
                if dryFor > 5, !spellDry { spellDry = true; shelteredSpells += 1 }
            } else if wasRough {
                endedAt = t
            }
            if let end = endedAt, t - end < 180, s.isStanding, !s.sheltered { outAfter += 1; endedAt = nil }
            if let end = endedAt, t - end >= 180 { endedAt = nil }
            wasRough = w.rough
            if let r = e.remains.last, r.id > lastRemains { lastRemains = r.id; remainsLeft += 1 }
            for r in e.remains where r.carrier != nil { carriedOff.insert(r.id) }
            for p in s.prey where p.hidden { hidAway.insert(p.id) }
            for p in s.prey where p.sheltering { tookCover.insert(p.id) }
            let k = s.debugErrandKind
            if env["PC_TRACE"] == "shelter", k == "shelter", Int(t * 60) % 300 == 0 {
                print(String(format: "          %6.0f (%.0f,%.0f) rain %.2f %@ | %@ | %@ | %@", Double(t), Double(s.worldPos.x), Double(s.worldPos.y), Double(w.rain), s.sheltered ? "sheltered" : "out", s.debugState, s.debugErrand, s.debugPlaceNote))
            }
            if k != last, env["PC_TRACE"] == "errands" || (env["PC_TRACE"] == "shelter" && (k == "shelter" || last == "shelter" || k == "emerge" || last == "emerge")) {
                print(String(format: "     %6.0f %@ -> %@  rain %.2f %@ | %@ | %@ | %@", Double(t), last ?? "-", k ?? "-", Double(w.rain), s.sheltered ? "sheltered" : "out", s.debugState, s.debugErrand, s.debugErrandEnd))
            }
            if k != last {
                if let k { kinds[k, default: 0] += 1 }
                since = t
                last = k
            }
            if k != nil { longest = max(longest, t - since) }
            offFor = s.isStanding && !footed(s, m) ? offFor + 1 : 0
            // (What it was about just before, should it come to be standing on nothing.)
            let a = s.standingOn
            recent.append(String(format: "       %7.2f (%.0f,%.0f) on %@ %@ | %@ | %@", Double(t), Double(s.worldPos.x), Double(s.worldPos.y),
                                 a.map { "\($0.loopID):\($0.segIdx)@\(Int($0.t))" } ?? "-", a.flatMap { m.worldPoint($0) }.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "-",
                                 s.debugState, s.debugErrand))
            if recent.count > 150 { recent.removeFirst(recent.count - 150) }
            // (Pouncing on something on the ground, it lands low and eases up
            // onto its footing over a few frames: only more than that counts.)
            if offFor == 18 {
                floating += 1
                print(String(format: "     standing on nothing at %.1fs; before it:", Double(t)))
                for (i, l) in recent.enumerated() where i % 10 == 0 || i == recent.count - 1 { print(l) }
            }
            if tracing, Int(t * 60) % 3600 == 0 {
                let loose = s.prey.filter { $0.state == .loose }
                print(String(format: "     %4.0f min fed %.2f hunting %@ | %@ | loose: %@", Double(t / 60), Double(s.debugFed), s.debugHuntTarget.map { "#\($0)" } ?? "-", s.debugState,
                             loose.map { "\($0.kind)#\($0.id)\($0.noticed ? "" : " unseen")\($0.hidden ? " hidden" : "") \(Int($0.pos.distance(to: s.worldPos)))" }.joined(separator: ", ")))
            }
        }
        print("  \(name): errands " + kinds.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: " "))
        print("     came in: " + arrived.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
              + "; caught \(caughtN); remains left \(remainsLeft), carried off by ants \(carriedOff.count); lay low \(hidAway.count), took cover \(tookCover.count)")
        print("     downpours \(downpours): sheltered in \(shelteredSpells), out again after \(outAfter); emerged ×\(kinds["emerge"] ?? 0)")
        b.check("\(name): in under something for each downpour, and out again after", downpours >= 2 && shelteredSpells >= downpours - 1 && outAfter >= downpours - 1,
                "\(shelteredSpells)/\(downpours) sheltered, \(outAfter) out after")
        b.check("\(name): drank rain off the leaves", (kinds["dew"] ?? 0) >= 1)
        b.check("\(name): creatures came and went, and it hunted some", arrived.count >= 4 && caughtN >= 2, "\(arrived.values.reduce(0, +)) came, \(caughtN) caught")
        b.check("\(name): never standing on nothing", floating == 0, "\(floating)")
        b.check("\(name): never stuck at one errand", longest < 420, String(format: "%.0fs", Double(longest)))
    }
}

/// Diagnostics: the spots under and by a table, and where shelter is sought from beside it.
private func probeSpots() {
    var h = tank()
    let table = put(.table, x: 1000, &h)
    let m = surfaces(h, standoff: standoff)
    let e = alive(h, map: m)
    print("table \(table.rect)")
    for sp in e.spots where sp.point.x > 940 && sp.point.x < 1070 && sp.point.y < G + 40 {
        print(String(format: "  (%.0f,%.0f) %@ open %.2f owner %d %@:%d", Double(sp.point.x), Double(sp.point.y), "\(sp.facing)", Double(sp.open), sp.owner, sp.anchor.loopID, sp.anchor.segIdx))
    }
    var hb = tank()
    let rock = put(.boulder, x: 1100, &hb)
    let mb = surfaces(hb, standoff: standoff)
    print("boulder \(rock.rect)")
    if let l = mb.loop("screen:0") {
        for (i, sg) in l.segs.enumerated() where max(sg.a.x, sg.b.x) > 990 && min(sg.a.x, sg.b.x) < 1180 && max(sg.a.y, sg.b.y) < 200 {
            let n = sg.dir.perp
            print(String(format: "  seg %d (%.1f,%.1f)->(%.1f,%.1f) len %.1f n (%.2f,%.2f) %@ beetle %@", i, Double(sg.a.x), Double(sg.a.y), Double(sg.b.x), Double(sg.b.y), Double(sg.len),
                         Double(n.x), Double(n.y), "\(sg.facing)", Prey.walkable(.beetle, normal: n) ? "ok" : "no"))
        }
    }
    let (hc, tc) = chainTank()
    let mc = surfaces(hc, standoff: standoff)
    print("chain tank table \(tc.rect) id \(tc.id)")
    for l in mc.loops where l.id.hasPrefix("item:\(tc.id)") {
        let b = l.segs.reduce(CGRect.null) { $0.union(CGRect(x: min($1.a.x, $1.b.x), y: min($1.a.y, $1.b.y), width: abs($1.b.x - $1.a.x) + 0.1, height: abs($1.b.y - $1.a.y) + 0.1)) }
        print("  loop \(l.id) closed \(l.closed) segs \(l.segs.count) box \(b)")
    }
    for j in mc.junctions where j.to.hasPrefix("item:\(tc.id)") || j.from.hasPrefix("item:\(tc.id)") {
        print(String(format: "  junction %@ v%d -> %@ v%d at (%.0f,%.0f)", j.from, j.fromVertex, j.to, j.toVertex, Double(j.at.x), Double(j.at.y)))
    }
    for k in [PreyKind.beetle, .worm] {
        var picks: [Int: Int] = [:]
        for _ in 0..<200 {
            if let s = e.haunt(.shelter, for: k, near: V2(1155, G + 12), within: 260 * scale, loop: "screen:0") { picks[Int(s.point.x), default: 0] += 1 }
        }
        print("  \(k): " + picks.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " "))
    }
}

func ecologyCheck() {
    var b = Builder()
    let parts = env["PC_PART"].map { Set($0.split(separator: ",").map(String.init)) }
    if parts?.contains("probe") == true { probeSpots(); return }
    if parts?.contains("sky") ?? true { skyCheck(&b) }
    if parts?.contains("sites") ?? true { sitesCheck(&b) }
    if parts?.contains("arrive") ?? true { arriveCheck(&b) }
    if parts?.contains("prey") ?? true { preyCheck(&b) }
    if parts?.contains("drops") ?? true { dropsCheck(&b) }
    if parts?.contains("chain") ?? true { chainCheck(&b) }
    if parts?.contains("sun") ?? true { sunCheck(&b) }
    if parts?.contains("wind") ?? true { windCheck(&b) }
    if parts?.contains("hunt") ?? true { huntCheck(&b) }
    if parts?.contains("mild") ?? true { mildCheck(&b) }
    if parts?.contains("life") ?? true { lifeCheck(&b) }
    print(b.fails == 0 ? "all ok" : "\(b.fails) FAILED")
}
#endif
