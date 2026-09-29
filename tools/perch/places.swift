import AppKit

// Places check (tools/perch.sh places): using the tank (Phase 5).
//
//   • survey: the places in a few tanks sized up — water at the dish, cover
//     in a cave, a built room counted as built, a lookout high with a view,
//     open floor exposed — and how long a big tank takes to size up;
//   • water: a dish put in a tank it knows. It discovers it, goes off about
//     its business, and later — thirsty in its own time — goes back to it
//     and drinks (the whole sequence, rings on the water and all);
//   • shelter: a bark cave put in; later a downpour, and it goes in there;
//   • built: a house it was given and a bark cave nearer — rain, bed time,
//     a fright: it goes to the house;
//   • fright: a shy one given a fright hides somewhere shut in, then comes out;
//   • lookout: a lookout put in; later it climbs it of its own accord to
//     look out from, scanning;
//   • life: a long life in a whole tank — its errands, a favourite place to
//     rest it keeps going back to, the ways it knows, never standing on
//     nothing, never stuck.
//
//   • more: dew sipped off a leaf after rain, warming up when cold, its
//     face in a mirror, the glass at the end of the tank;
//   • memory: what it knows of its places saved and read back, and an old
//     save (from before places) still read.
//
// PC_PART=survey,water,shelter,built,fright,lookout,more,memory,life  PC_SEEDS (4)  PC_TRACE=1
// PC_FILM=prefix (a film strip of the first drink)  PC_LIFE=secs (2400)  PC_LOOK=mine (dressed as in the app)
// Diagnostics: PC_PART=probe (survey cover vs the spider's own sense of shelter), applike (the app test's tank)

#if SHAPED
private let G = HabitatLayout.ground
private let scale: CGFloat = 0.78

/// A spider in `h`, knowing everything in it already, on the floor at `x`.
private func settle(_ h: Habitat, personality: Personality, at x: CGFloat) -> (SurfaceMap, Spider) {
    let standoff = 22 * scale
    let desk = SurfaceMap()
    desk.standoff = standoff
    desk.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 25, windows: [])
    let tank = surfaces(h, standoff: standoff)
    let s = Spider(map: desk)
    s.config.followCursor = false
    s.config.scale = scale
    var d = s.design
    d.personality = personality
    // PC_LOOK=mine: dressed as the spider in the app is (read only).
    if env["PC_LOOK"] == "mine", let data = UserDefaults(suiteName: "com.gabriel.desktopspider")?.data(forKey: SpiderDesign.key),
       let mine = try? JSONDecoder().decode(SpiderDesign.self, from: data) {
        d.look = mine.look
    }
    s.apply(design: d)
    s.knowledge = HabitatKnowledge()
    for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
    s.enter(map: tank, at: V2(x, G + 30), habitat: true)
    s.tankRebuilt(h, smooth: false, inIt: true)
    return (tank, s)
}

private func plainTank(_ width: CGFloat = 2400) -> Habitat {
    var h = Habitat(biome: .forest, world: CGSize(width: width, height: 700))
    _ = h.add(.rock, at: CGPoint(x: 260, y: 0))
    _ = h.add(.fern, at: CGPoint(x: width - 240, y: 0))
    return h
}

/// Something put in (new to it), and the tank laid out again.
@discardableResult
private func putIn(_ kind: HabitatItemKind, x: CGFloat, y: CGFloat = 0, _ h: inout Habitat, _ m: SurfaceMap, _ s: Spider) -> HabitatItem {
    var it = h.add(kind, at: CGPoint(x: x, y: y))
    it.seed = 7
    h.items[h.items.count - 1] = it
    m.rebuild(habitat: h.surfaces(standoff: m.standoff))
    s.tankRebuilt(h, smooth: false, inIt: true)
    return it
}

private func run(_ s: Spider, _ secs: CGFloat, each: ((CGFloat) -> Bool)? = nil) {
    var t: CGFloat = 0
    for _ in 0..<Int(secs / dt) {
        s.setCursor(V2(-4000, -4000))
        s.update(dt: dt)
        t += dt
        if let each, !each(t) { return }
    }
}

private func gap(_ it: HabitatItem, _ p: V2) -> CGFloat {
    let r = it.rect
    return V2(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY)).length
}

private func footed(_ s: Spider, _ m: SurfaceMap) -> Bool {
    guard let a = s.standingOn, let p = m.worldPoint(a) else { return false }
    return p.distance(to: s.worldPos) < 16
}

private let presets: [String: Personality] = Dictionary(uniqueKeysWithValues: Personality.presets.map { ($0.name, $0.p) })
private func who(_ names: [String]) -> [(String, Personality)] {
    let wanted = env["PC_WHO"].map { Set($0.split(separator: ",").map(String.init)) }
    return (["Default"] + names).filter { wanted?.contains($0) ?? true }.map { ($0, $0 == "Default" ? Personality() : presets[$0]!) }
}

// MARK: Survey

/// A small house: a room downstairs (backing wall, a door open on the left,
/// a wall on the right, floorboards over it), a bed in it.
private func house(_ b: inout Builder, x X: CGFloat) -> (room: CGRect, bed: Int) {
    func put(_ kind: HabitatItemKind, x: CGFloat, y: CGFloat, w: CGFloat? = nil, h: CGFloat? = nil, flipped: Bool = false) -> Int {
        var it = b.h.add(kind, at: CGPoint(x: x, y: y))
        if let w { it.w = w }
        if let h { it.h = h }
        it.x = x; it.y = y; it.flipped = flipped
        it.seed = 500 + it.id * 13
        Habitat.clamp(&it, in: b.h.size)
        b.h.items[b.h.items.count - 1] = it
        return it.id
    }
    _ = put(.woodBacking, x: X, y: 0, w: 300, h: 150)
    _ = put(.door, x: X - 150, y: 0, flipped: true)
    _ = put(.wall, x: X + 150, y: 0)
    let floor = b.drop(.floorboards, x: X + 5, y: 150 + 8, width: 330, expectSnap: false)
    b.h.linkWhatTouches(floor, within: 2)
    let bed = put(.bed, x: X - 40, y: 0)
    let top = b.h.item(id: floor)!.rect.minY
    return (CGRect(x: X - 135, y: G, width: 270, height: top - G), bed)
}

private func surveyCheck(_ b: inout Builder) {
    print("== survey: what places offer")
    var h = plainTank()
    let dish = h.add(.waterDish, at: CGPoint(x: 700, y: 0))
    let cave = h.add(.barkCave, at: CGPoint(x: 1100, y: 0))
    let look = h.add(.lookout, at: CGPoint(x: 1600, y: 0))
    let m = surfaces(h, standoff: 22 * scale)
    let sv = PlaceSurvey(h, map: m, scale: scale)
    print("  \(sv.places.count) places, \(sv.water.count) water, walkable loops \(sv.walkable.count)/\(m.loops.count)")
    let drinks = sv.places.filter { $0.kind == .drinkEdge }
    b.check("the dish: somewhere to drink from, with water there", !drinks.isEmpty && drinks.allSatisfy { $0.thing == dish.id && $0.q[.water] == 1 }
            && sv.water.first?.id == dish.id, "\(drinks.count) drinking spots")
    b.check("…looking at the water", drinks.allSatisfy { f in dish.water.map { $0.insetBy(dx: -2, dy: -2).contains(f.focus!.point) } ?? false })
    let inCave = sv.places.filter { $0.thing == cave.id && ($0.kind == .interior || $0.roofOwner == cave.id) }
    let bestCave = inCave.max { $0.q[.shelter] < $1.q[.shelter] }
    b.check("in the bark cave: sheltered, covered, shut in", (bestCave?.q[.shelter] ?? 0) > 0.6 && (bestCave?.q[.enclosure] ?? 0) > 0.4,
            bestCave.map { "\($0.q)" } ?? "none")
    b.check("…natural: not built", (bestCave?.q[.made] ?? 1) < 0.1)
    let tops = sv.places.filter { $0.owner == look.id && $0.standing && $0.q[.elevation] > 0.7 }
    let bestTop = tops.max { $0.q[.visibility] < $1.q[.visibility] }
    b.check("up the lookout: high, with a view", (bestTop?.q[.visibility] ?? 0) > 0.6, bestTop.map { "\($0.q)" } ?? "none")
    let open = sv.places.filter { $0.owner == 0 && $0.standing && abs($0.point.x - 1350) < 40 }
    b.check("open floor: exposed, no cover", open.allSatisfy { $0.q[.exposure] > 0.8 && $0.q[.cover] < 0.1 }, open.first.map { "\($0.q)" } ?? "none")
    let want = PlaceWant(use: .lookout, from: V2(1350, G + 17), scale: scale, personality: Personality())
    let best = sv.ranked(want) { _ in PlaceSense() }.first
    b.check("the best lookout is up the lookout", best?.place.owner == look.id, best.map { "\($0.place.key) \($0.score)" } ?? "none")

    // A house: its room is built shelter.
    var hb = Builder()
    let hs = house(&hb, x: 900)
    _ = hb.h.add(.barkCave, at: CGPoint(x: 1500, y: 0))
    let hm = surfaces(hb.h, standoff: 22 * scale)
    let hsv = PlaceSurvey(hb.h, map: hm, scale: scale)
    let room = hsv.places.filter { $0.standing && hs.room.contains($0.point.point) }
    let roomMade = room.map { $0.q[.made] }.max() ?? 0
    b.check("in the house: the room is built shelter", roomMade > 0.6 && room.contains { $0.q[.cover] > 0.6 }, String(format: "made %.2f, %d places", roomMade, room.count))
    b.check("…reachable on foot", room.contains { $0.q[.access] == 1 })

    // How long a whole tank takes.
    let big = Habitat.preset(.forestFloor, world: world)
    let bm = surfaces(big, standoff: 22 * scale)
    let t0 = Date()
    let bsv = PlaceSurvey(big, map: bm, scale: scale)
    let ms = Date().timeIntervalSince(t0) * 1000
    print(String(format: "  forest floor (%d things): %d places sized up in %.0f ms", big.items.count, bsv.places.count, ms))
    b.check("a whole tank sized up quickly", ms < 400, String(format: "%.0f ms", ms))
}

// MARK: Water

private struct Film {
    var frames: [(SpiderPose, String)] = []
    mutating func shot(_ s: Spider, _ tag: String) { if frames.count < 42 { frames.append((s.pose(), tag)) } }
    func save(_ path: String, h: Habitat, area: CGRect) {
        guard !frames.isEmpty else { return }
        let cols = 6, zoom: CGFloat = 3
        let rows = (frames.count + cols - 1) / cols
        let cw = Int(area.width * zoom), chH = Int(area.height * zoom)
        guard let c = CGContext(data: nil, width: cw * cols, height: chH * rows, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        for (n, f) in frames.enumerated() {
            let ox = CGFloat(n % cols * cw), oy = CGFloat((rows - 1 - n / cols) * chH)
            c.saveGState()
            c.translateBy(x: ox, y: oy)
            c.clip(to: CGRect(x: 0, y: 0, width: cw, height: chH))
            c.scaleBy(x: zoom, y: zoom)
            c.setFillColor(NSColor(calibratedRed: 0.55, green: 0.7, blue: 0.62, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: area.size))
            c.setFillColor(NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.18, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: area.width, height: G - area.minY))
            paintItems(h, area: area, scale: scale, c)
            c.translateBy(x: -area.minX, y: -area.minY)
            let side = SpiderRenderer.spriteSide(for: f.0.scale)
            SpiderRenderer.draw(f.0, in: c, bounds: CGRect(x: f.0.pos.x - side / 2, y: f.0.pos.y - side / 2, width: side, height: side))
            c.restoreGState()
            c.saveGState()
            c.translateBy(x: ox, y: oy)
            label(c, f.1, at: CGPoint(x: 4, y: CGFloat(chH) - 14))
            c.restoreGState()
        }
        if let img = c.makeImage() { perchSave(img, path) }
    }
}

private func perchSave(_ img: CGImage, _ path: String) { save(img, path) }

private func waterCheck(_ b: inout Builder) {
    print("== water: a dish put in; later, thirsty, it goes back for a drink")
    let seeds = Int(env["PC_SEEDS"] ?? "4") ?? 4
    let trace = env["PC_TRACE"] != nil
    for (name, p) in who(["Curious", "Shy", "Lazy", "Hyper"]) {
        var full = 0, rows: [String] = []
        for sd in 0..<seeds {
            reseed(UInt64(900 + sd))
            var h = plainTank()
            let (m, s) = settle(h, personality: p, at: 1500)
            run(s, 3)
            s.debugSetUrges(thirst: 0.05)
            let dish = putIn(.waterDish, x: 900, &h, m, s)
            let know = s.knowledge!
            let water = dish.water!
            var noticed: CGFloat?, awayAt: CGFloat?, drank: CGFloat?, drinks = 0, wasDrinking = false
            var seq: [String] = [], lastAct = "", floating = 0, offFor = 0, ringsSeen = false
            var film = Film()
            var nextShot: CGFloat = 0
            let filming = env["PC_FILM"] != nil && sd == 0 && name == "Default"
            run(s, 1500) { t in
                if noticed == nil, know.stage(of: dish.uid) != .unknown { noticed = t }
                if noticed != nil, drank == nil, awayAt == nil, gap(dish, s.worldPos) > 120 { awayAt = t }
                let drinking = s.debugDrinking && s.debugSipAt.map { water.insetBy(dx: -6, dy: -6).contains($0.point) } == true
                if drinking, !wasDrinking {
                    drinks += 1
                    if drank == nil, s.debugErrandKind == "drink" { drank = t }
                }
                wasDrinking = drinking
                if s.debugErrandKind == "drink" || drinking {
                    let a = s.debugState.split(separator: ":").dropFirst().first?.split(separator: " ").first.map(String.init) ?? "?"
                    if a != lastAct { seq.append(a); lastAct = a }
                    if s.pose().specks.contains(where: { $0.kind == .ring }) { ringsSeen = true }
                    if filming, drank == nil || t < drank! + 12, gap(dish, s.worldPos) < 40, t >= nextShot {
                        nextShot = t + 0.4
                        film.shot(s, String(format: "%.1fs %@", Double(t), a))
                    }
                }
                offFor = s.isStanding && !footed(s, m) ? offFor + 1 : 0
                if offFor == 6 { floating += 1 }
                if trace, Int(t * 60) % 600 == 0 { print(String(format: "      %6.1f %@ | %@ | thirst %.2f", Double(t), s.debugState, s.debugErrand, Double(s.debugUrges.thirst))) }
                return drank == nil || t < drank! + 20
            }
            if filming { film.save("\(env["PC_FILM"]!)_drink.png", h: h, area: CGRect(x: water.midX - 70, y: G - 10, width: 140, height: 80)) }
            let ok = noticed != nil && awayAt != nil && drank != nil && drank! > noticed! && floating == 0
            if ok { full += 1 }
            func f(_ x: CGFloat?) -> String { x.map { String(format: "%6.1f", Double($0)) } ?? "     -" }
            rows.append("     \(sd)  noticed \(f(noticed))  away \(f(awayAt))  drank \(f(drank))  drinks \(drinks)  rings \(ringsSeen)  [\(seq.prefix(14).joined(separator: " "))]")
        }
        print("  \(name)")
        rows.forEach { print($0) }
        b.check("\(name): discovers the dish, goes off, later comes back and drinks", full >= seeds - 1, "\(full)/\(seeds)")
    }
}

// MARK: Shelter

private func shelterCheck(_ b: inout Builder) {
    print("== shelter: a bark cave put in; later a downpour, and in it goes")
    let seeds = Int(env["PC_SEEDS"] ?? "4") ?? 4
    for (name, p) in who(["Shy", "Show-off"]) {
        var inside = 0, rows: [String] = []
        for sd in 0..<seeds {
            reseed(UInt64(1100 + sd))
            var h = plainTank()
            let (m, s) = settle(h, personality: p, at: 1600)
            run(s, 3)
            let cave = putIn(.barkCave, x: 1100, &h, m, s)
            let know = s.knowledge!
            var noticed: CGFloat?
            run(s, 300) { t in
                if noticed == nil, know.stage(of: cave.uid) != .unknown { noticed = t }
                return true
            }
            // Wherever it is by then: away from it, if it is in it.
            if gap(cave, s.worldPos) < 150, let spot = m.nearestSpot(to: V2(1650, G + 22 * scale), within: 60) {
                s.debugAttach(loopID: spot.anchor.loopID, segIdx: spot.anchor.segIdx, t: spot.anchor.t, dir: 1)
                run(s, 1)
            }
            s.weather = WeatherFeel(rain: 0.9)
            var sheltered: CGFloat?, where_ = ""
            run(s, 90) { t in
                if s.sheltered, s.isStanding, gap(cave, s.worldPos) < 30 { sheltered = t; where_ = s.debugErrand; return false }
                return true
            }
            if noticed != nil, sheltered != nil { inside += 1 }
            rows.append(String(format: "     %d  noticed %@  in the cave %@ after the rain began  %@", sd, noticed.map { String(format: "%.0fs", Double($0)) } ?? "never",
                               sheltered.map { String(format: "%.1fs", Double($0)) } ?? "never", where_.isEmpty ? s.debugErrand : where_))
        }
        print("  \(name)")
        rows.forEach { print($0) }
        b.check("\(name): discovers the cave, and shelters in it when it pours", inside >= seeds - 1, "\(inside)/\(seeds)")
    }
}

// MARK: Built shelter first

private func builtCheck(_ b: inout Builder) {
    print("== built: the house before the cave (the cave nearer)")
    var hb = Builder()
    let hs = house(&hb, x: 900)
    let cave = hb.h.add(.barkCave, at: CGPoint(x: 1500, y: 0))
    let caveRect = cave.rect
    if env["PC_TRACE"] != nil {
        let hm = surfaces(hb.h, standoff: 22 * scale)
        let sv = PlaceSurvey(hb.h, map: hm, scale: scale)
        for use in [PlaceUse.shelter, .sleep, .hide] {
            var want = PlaceWant(use: use, from: V2(1290, G + 17), scale: scale, personality: Personality())
            want.threat = use == .hide ? V2(1250, G + 200) : nil
            want.rough = use == .shelter
            print("  top for \(use):")
            for r in sv.ranked(want, top: 10, sense: { _ in PlaceSense() }) {
                let inRoom = hs.room.insetBy(dx: -20, dy: -10).contains(r.place.point.point)
                print("    " + String(format: "%.2f (%.0f,%.0f)", Double(r.score), Double(r.place.point.x), Double(r.place.point.y))
                      + " \(r.place.key.suffix(22)) \(inRoom ? "ROOM" : "") owner \(r.place.owner) roof \(r.place.roofOwner)  \(r.place.q)")
            }
        }
        print("  room \(hs.room), cave \(caveRect)")
    }
    // Choosing, many times over, from between them (nearer the cave).
    for (use, label) in [(PlaceUse.shelter, "shelter from rain"), (.sleep, "sleep"), (.hide, "hide from a fright")] {
        var house = 0, cv = 0, other = 0
        for sd in 0..<60 {
            reseed(UInt64(1300 + sd))
            let (_, s) = settle(hb.h, personality: sd % 2 == 0 ? Personality() : presets["Shy"]!, at: 1290)
            run(s, 0.5)
            if use == .shelter { s.weather = WeatherFeel(rain: 0.9) }
            guard let pl = s.debugChoose(use, threat: use == .hide ? V2(1250, G + 200) : nil) else { other += 1; continue }
            // (The house: anywhere its cover or its furniture is what was built.)
            if pl.q[.made] >= 0.5 || pl.thing == hs.bed { house += 1 }
            else if caveRect.insetBy(dx: -30, dy: -30).contains(pl.point.point) { cv += 1 } else { other += 1 }
        }
        print("  \(label): house \(house), cave \(cv), elsewhere \(other) (of 60)")
        b.check("\(label): the house first", house >= 42 && house > cv * 3, "house \(house) cave \(cv)")
    }
    // And for real: rain, and where it runs to.
    var toHouse = 0, toCave = 0
    let seeds = Int(env["PC_SEEDS"] ?? "4") ?? 4
    for sd in 0..<seeds {
        reseed(UInt64(1400 + sd))
        let (_, s) = settle(hb.h, personality: Personality(), at: 1290)
        run(s, 2)
        s.weather = WeatherFeel(rain: 0.9)
        var lastLine = "", dry: CGFloat = 0, cavesNow = 0
        run(s, 90) { t in
            if env["PC_TRACE"] != nil {
                let line = "\(s.debugState) | \(s.debugErrand) | \(s.sheltered ? "sheltered" : "out")"
                if line != lastLine || (env["PC_TRACE"] == "2" && Int(t * 60) % 60 == 0) {
                    print(String(format: "      %5.1f (%.0f,%.0f) %@ %@", Double(t), Double(s.worldPos.x), Double(s.worldPos.y), line, s.debugActivity))
                    lastLine = line
                }
            }
            // Settled under cover a few seconds: under what?
            if s.sheltered, s.isStanding { dry += dt } else { dry = 0 }
            if dry > 4, let here = s.debugPlaces?.nearest(to: s.worldPos, within: 24) {
                if here.q[.made] >= 0.5 { toHouse += 1; cavesNow = 0; return false }
                if caveRect.insetBy(dx: -30, dy: -30).contains(s.worldPos.point) { cavesNow = 1 }
            }
            return true
        }
        toCave += cavesNow
        if env["PC_TRACE"] != nil { print("      end: \(s.debugPlaceNote) | \(s.debugState) | \(s.debugErrand) | \(s.debugWeather)") }
    }
    print("  in the rain for real: into the house \(toHouse), the cave \(toCave) (of \(seeds))")
    b.check("in the rain it goes into the house", toHouse >= seeds - 1, "\(toHouse)/\(seeds)")

    // A table further off than a cave: under the table.
    var h = plainTank(2400)
    let table = h.add(.table, at: CGPoint(x: 780, y: 0))
    let cave2 = h.add(.barkCave, at: CGPoint(x: 1460, y: 0))
    var under = 0, inCave = 0
    for sd in 0..<30 {
        reseed(UInt64(1450 + sd))
        let (_, s) = settle(h, personality: sd % 2 == 0 ? Personality() : presets["Shy"]!, at: 1200)
        run(s, 0.5)
        s.weather = WeatherFeel(rain: 0.9)
        guard let pl = s.debugChoose(.shelter) else { continue }
        if pl.roofOwner == table.id { under += 1 } else if gap(cave2, pl.point) < 30 { inCave += 1 }
    }
    print("  a table (420 off) or a bark cave (260 off): under the table \(under), the cave \(inCave) (of 30)")
    b.check("under a table sooner than in a nearer cave", under >= 24, "\(under)/30")
}

// MARK: Fright

private func frightCheck(_ b: inout Builder) {
    print("== fright: a timid one hides, then comes out")
    let seeds = (Int(env["PC_SEEDS"] ?? "4") ?? 4) + 2
    var hid = 0, out = 0, rows: [String] = []
    for sd in 0..<seeds {
        reseed(UInt64(1500 + sd))
        var h = plainTank()
        _ = h.add(.barkCave, at: CGPoint(x: 1300, y: 0))
        let (_, s) = settle(h, personality: presets["Shy"]!, at: 1650)
        run(s, 4)
        let from = s.worldPos + V2(120, 160)
        s.noticeCommotion(at: from, fright: true)
        var hiding: CGFloat?, enclosed: CGFloat = 0, over: CGFloat?
        var lastLine = ""
        run(s, 150) { t in
            if env["PC_TRACE"] != nil {
                let line = "\(s.debugState) | \(s.debugErrand)"
                if line != lastLine { print(String(format: "      %6.2f %@", Double(t), line)); lastLine = line }
            }
            if s.debugErrandKind == "hide", s.debugErrand.contains(" act "), hiding == nil {
                hiding = t
                enclosed = s.debugErrandPlace?.q[.enclosure] ?? 0
            }
            if hiding != nil, s.debugErrandKind == nil { over = t; return false }
            return true
        }
        if env["PC_TRACE"] != nil { print("      hide note: \(s.debugPlaceNote)") }
        if hiding != nil, enclosed >= 0.3 { hid += 1 }
        if over != nil { out += 1 }
        rows.append(String(format: "     %d  hiding %@ (shut in %.2f)  out again %@", sd, hiding.map { String(format: "%.1fs", Double($0)) } ?? "never",
                           Double(enclosed), over.map { String(format: "%.0fs", Double($0)) } ?? "never"))
    }
    rows.forEach { print($0) }
    b.check("a shy one hides somewhere shut in after a fright", hid >= seeds - 2, "\(hid)/\(seeds)")
    b.check("…and comes out again", out >= hid, "\(out)/\(hid)")
}

// MARK: Lookout

private func lookoutCheck(_ b: inout Builder) {
    print("== lookout: put in; later it climbs it, of its own accord, to look out")
    let seeds = Int(env["PC_SEEDS"] ?? "4") ?? 4
    for (name, p) in who(["Curious", "Lazy"]) {
        var used = 0, rows: [String] = []
        for sd in 0..<seeds {
            reseed(UInt64(1700 + sd))
            var h = plainTank()
            let (m, s) = settle(h, personality: p, at: 1700)
            run(s, 3)
            s.debugSetUrges(view: 0)
            let look = putIn(.lookout, x: 1100, &h, m, s)
            let know = s.knowledge!
            var noticed: CGFloat?, up: CGFloat?, scans: [V2] = [], wasAway = false
            run(s, 1500) { t in
                if noticed == nil, know.stage(of: look.uid) != .unknown { noticed = t }
                if noticed != nil, gap(look, s.worldPos) > 150 { wasAway = true }
                if s.debugErrandKind == "lookout", let pl = s.debugErrandPlace, pl.owner == look.id, s.debugErrand.contains(" act "),
                   s.debugUnderfoot == look.id {
                    if up == nil { up = t }
                    if let e = s.debugEyeOn {
                        let d = (e - s.worldPos).normalized
                        if !scans.contains(where: { $0.dot(d) > 0.9 }) { scans.append(d) }
                    }
                }
                return up == nil || t < up! + 40
            }
            _ = m
            let ok = noticed != nil && up != nil && up! > noticed! && wasAway && scans.count >= 3
            if ok { used += 1 }
            rows.append(String(format: "     %d  noticed %@  up it to look out %@  directions watched %d", sd,
                               noticed.map { String(format: "%.0fs", Double($0)) } ?? "never", up.map { String(format: "%.0fs", Double($0)) } ?? "never", scans.count))
        }
        print("  \(name)")
        rows.forEach { print($0) }
        b.check("\(name): discovers the lookout, later climbs it to look out, scanning", used >= seeds - 1, "\(used)/\(seeds)")
    }
}

// MARK: A life

private func lifeCheck(_ b: inout Builder) {
    let secs = CGFloat(Double(env["PC_LIFE"] ?? "2400") ?? 2400)
    print("== life: \(Int(secs / 60)) minutes in a whole tank")
    for (name, p) in who(["Lazy", "Curious"]) {
        reseed(UInt64(2000))
        let h = Habitat.preset(.forestFloor, world: world)
        let (m, s) = settle(h, personality: p, at: world.width / 2)
        var kinds: [String: Int] = [:], rests: [String: Int] = [:], restOrder: [String] = []
        var last: String?, lastKey = "", floating = 0, offFor = 0, longest: CGFloat = 0, since: CGFloat = 0
        // (You about for ten minutes, then away for ten: left alone, it
        // settles down to sleep.)
        var t = CGFloat(0)
        for _ in 0..<Int(secs / dt) {
            if Int(t / 600) % 2 == 0 { s.setCursor(V2(-4000, -4000)) }
            s.update(dt: dt)
            t += dt
            let k = s.debugErrandKind
            let key = s.debugErrandPlace?.key ?? ""
            if k != last || (k != nil && key != lastKey && k != "round") {
                if let k {
                    kinds[k, default: 0] += 1
                    if k == "rest" || k == "sleep" { rests[key, default: 0] += 1; restOrder.append(key) }
                }
                since = t
                last = k
                lastKey = key
            }
            if k != nil { longest = max(longest, t - since) }
            offFor = s.isStanding && !footed(s, m) ? offFor + 1 : 0
            if offFor == 6 { floating += 1 }
        }
        let know = s.knowledge!
        let top = rests.max { $0.value < $1.value }
        let later = restOrder.dropFirst(min(2, restOrder.count))
        let share = top.map { t in CGFloat(later.filter { $0 == t.key }.count) / CGFloat(max(later.count, 1)) } ?? 0
        let routes = know.state.routes.values.sorted(by: >)
        print("  \(name): errands \(kinds.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: " "))")
        print(String(format: "     rests/sleeps %d at %d places; favourite %@ ×%d (%.0f%% of later ones)", restOrder.count, rests.count, top?.key ?? "-",
                     top?.value ?? 0, Double(share * 100)))
        print("     favourites: \(s.debugFavourites.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "; "))")
        print(String(format: "     ways known %d, best %.2f; places remembered %d; longest errand %.0fs", routes.count, Double(routes.first ?? 0),
                     know.places.count, Double(longest)))
        b.check("\(name): lives a varied life (many kinds of errand)", kinds.count >= 8, "\(kinds.count) kinds")
        b.check("\(name): a favourite spot to rest it keeps going back to", (top?.value ?? 0) >= 3 && share >= 0.3,
                String(format: "×%d, %.0f%%", top?.value ?? 0, Double(share * 100)))
        b.check("\(name): comes to know its ways about", (routes.first ?? 0) > 0.4, String(format: "best %.2f", Double(routes.first ?? 0)))
        b.check("\(name): never standing on nothing", floating == 0, "\(floating)")
        b.check("\(name): never stuck at one errand", longest < 420, String(format: "%.0fs", Double(longest)))
    }
}

/// Where the survey says there is cover, and whether the spider, put there
/// in the rain, finds itself sheltered.
private func coverProbe() {
    var h = plainTank()
    let cave = h.add(.barkCave, at: CGPoint(x: 1100, y: 0))
    let (m, s) = settle(h, personality: Personality(), at: 1600)
    guard let sv = s.debugPlaces else { return }
    var agree = 0, differ: [String] = []
    for pl in sv.places where pl.q[.cover] >= 0.35 && gap(cave, pl.point) < 60 {
        s.debugAttach(loopID: pl.anchor.loopID, segIdx: pl.anchor.segIdx, t: pl.anchor.t, dir: 1)
        s.weather = WeatherFeel(rain: 0.9)
        for _ in 0..<30 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
        if s.sheltered { agree += 1 } else { differ.append(String(format: "(%.0f,%.0f) %@ cover %.2f roof %d now (%.0f,%.0f)", Double(pl.point.x), Double(pl.point.y), pl.kind?.rawValue ?? "spot", Double(pl.q[.cover]), pl.roofOwner, Double(s.worldPos.x), Double(s.worldPos.y))) }
    }
    _ = m
    print("cover probe: \(agree) agree; differ \(differ.count)")
    differ.prefix(12).forEach { print("  " + $0) }
}

// MARK: More

/// Runs until `done` or `secs`, true if `done` held.
private func until(_ s: Spider, _ secs: CGFloat, _ done: @escaping () -> Bool) -> CGFloat? {
    var at: CGFloat?
    run(s, secs) { t in
        if done() { at = t; return false }
        return true
    }
    return at
}

private func moreCheck(_ b: inout Builder) {
    print("== more: dew, warmth, a mirror, the glass")
    let seeds = Int(env["PC_SEEDS"] ?? "4") ?? 4
    // Dew: rain, then it clears; no water dish — a sip off a leaf.
    var dew = 0
    for sd in 0..<seeds {
        reseed(UInt64(2500 + sd))
        var h = plainTank()
        _ = h.add(.broadLeaf, at: CGPoint(x: 1300, y: 0))
        _ = h.add(.mossPlatform, at: CGPoint(x: 1700, y: 0))
        let (_, s) = settle(h, personality: Personality(), at: 1500)
        s.weather = WeatherFeel(rain: 0.5)
        run(s, 20)
        s.weather = .calm
        s.debugSetUrges(thirst: 0.6)
        let got = until(s, 600) { s.debugErrandKind == "dew" && s.debugDrinking }
        if got != nil { dew += 1 }
        print(String(format: "  dew %d: sipped a drop off a leaf %@", sd, got.map { String(format: "at %.0fs", Double($0)) } ?? "never"))
    }
    b.check("after rain, it sips the drops off the leaves", dew >= seeds - 1, "\(dew)/\(seeds)")
    // Cold: over to the warm to warm up.
    var warmed = 0
    for sd in 0..<seeds {
        reseed(UInt64(2600 + sd))
        var h = plainTank()
        _ = h.add(.baskingStone, at: CGPoint(x: 1150, y: 0))
        _ = h.add(.floorLamp, at: CGPoint(x: 1900, y: 0))
        let (_, s) = settle(h, personality: Personality(), at: 1500)
        s.weather = WeatherFeel(cold: 0.9)
        let got = until(s, 400) { s.debugErrandKind == "bask" && s.debugErrand.contains(" act ") && (s.debugErrandPlace?.q[.warmth] ?? 0) >= 0.3 }
        if got != nil { warmed += 1 }
        print(String(format: "  cold %d: to the warm %@", sd, got.map { String(format: "at %.0fs", Double($0)) } ?? "never"))
    }
    b.check("in the cold it goes somewhere warm", warmed >= seeds - 1, "\(warmed)/\(seeds)")
    // A mirror on the wall: it squares up to its reflection.
    var shown = 0
    for sd in 0..<seeds {
        reseed(UInt64(2700 + sd))
        var h = plainTank()
        _ = h.add(.woodBacking, at: CGPoint(x: 1250, y: 0))
        var m = h.add(.mirror, at: CGPoint(x: 1250, y: 40))
        m.y = 40
        h.items[h.items.count - 1] = m
        let (_, s) = settle(h, personality: presets["Show-off"]!, at: 1500)
        let got = until(s, 900) { s.debugErrandKind == "mirror" && s.debugErrand.contains(" act ") && s.debugState.contains("armsUp") }
        if got != nil { shown += 1 }
        print(String(format: "  mirror %d: displays at its reflection %@", sd, got.map { String(format: "at %.0fs", Double($0)) } ?? "never"))
    }
    b.check("a bold one displays at itself in a mirror", shown >= seeds - 1, "\(shown)/\(seeds)")
    // The glass at the ends of the tank: places there, and it goes to peer out.
    let h = Habitat.preset(.forestFloor, world: world)
    let (_, s0) = settle(h, personality: Personality(), at: world.width / 2)
    let glass = s0.debugPlaces?.places.filter { $0.glass && !$0.hanging } ?? []
    let ends = Set(glass.map { $0.point.x < world.width / 2 })
    b.check("the glass at both ends of a whole tank is somewhere to go", ends.count == 2, "\(glass.count) spots")
    var peered = 0
    for sd in 0..<seeds {
        reseed(UInt64(2800 + sd))
        let (_, s) = settle(plainTank(), personality: presets["Curious"]!, at: 1500)
        let got = until(s, 900) { s.debugErrandKind == "glass" && s.debugErrand.contains(" act ") }
        if got != nil { peered += 1 }
    }
    b.check("now and then it goes to the glass to peer out", peered >= seeds - 1, "\(peered)/\(seeds)")
}

// MARK: Memory

private func memoryCheck(_ b: inout Builder) {
    print("== memory: kept and read back")
    reseed(2900)
    let h = Habitat.preset(.forestFloor, world: world)
    let (_, s) = settle(h, personality: presets["Lazy"]!, at: world.width / 2)
    run(s, 900)
    let know = s.knowledge!
    let d = UserDefaults(suiteName: "perch.places.test")!
    know.save(to: d, keeping: h)
    let back = HabitatKnowledge.load(from: d)
    b.check("its places, fondness and ways come back as they were", back.places.count == know.places.count && back.state.routes == know.state.routes
            && back.places.allSatisfy { k, r in know.record(k).map { $0.fond == r.fond && $0.visits == r.visits } ?? false },
            "\(back.places.count) places, \(back.state.routes.count) ways")
    // A save from before it knew places.
    let old = #"{"version":1,"things":{"abc":{"stage":"familiar","exposure":1,"unease":0,"kind":"rock"}},"kinds":{"rock":0.35},"seeded":true}"#
    let oldState = try? JSONDecoder().decode(HabitatKnowledge.State.self, from: Data(old.utf8))
    b.check("an older save still reads", oldState?.things["abc"]?.stage == .familiar && oldState?.seeded == true && oldState?.places.isEmpty == true)
    d.removePersistentDomain(forName: "perch.places.test")
}

func placesCheck() {
    var b = Builder()
    let parts = env["PC_PART"].map { Set($0.split(separator: ",").map(String.init)) }
    if parts?.contains("probe") == true { coverProbe(); return }
    if parts?.contains("applike") == true {
        // The real app's test tank: what it goes up to look out from.
        let W = world.width
        var h = Habitat(biome: .forest, world: world)
        _ = h.add(.rock, at: CGPoint(x: W / 2 - 900, y: 0))
        _ = h.add(.table, at: CGPoint(x: W / 2 - 420, y: 0))
        _ = h.add(.barkCave, at: CGPoint(x: W / 2 + 260, y: 0))
        let look = h.add(.lookout, at: CGPoint(x: W / 2 + 760, y: 0))
        for sd in 0..<6 {
            reseed(UInt64(3000 + sd))
            let (_, s) = settle(h, personality: Personality(), at: W / 2 - 330)
            run(s, 1)
            s.debugSetUrges(thirst: 0, view: 1.3, rest: 0, roam: 0)
            var line = "", up = false
            run(s, 120) { t in
                let l = "\(s.debugState) | \(s.debugErrand)"
                if l != line, env["PC_TRACE"] != nil { print(String(format: "   %6.1f %@", Double(t), l)) }
                if env["PC_TRACE"] == "2", Int(t * 60) % 30 == 0 { print(String(format: "      %6.1f pos %.0f,%.0f %@ %@", Double(t), Double(s.worldPos.x), Double(s.worldPos.y), s.debugWalk, s.debugActivity)) }
                line = l
                if s.debugErrandKind == "lookout", s.debugUnderfoot == look.id { up = true; return false }
                return true
            }
            let pick = s.debugChoose(.lookout)
            print("  seed \(sd): up the lookout \(up); would choose \(pick?.key ?? "-") owner \(pick?.owner ?? -1) (lookout #\(look.id)) now \(s.debugErrand)")
        }
        return
    }
    if parts?.contains("survey") ?? true { surveyCheck(&b) }
    if parts?.contains("water") ?? true { waterCheck(&b) }
    if parts?.contains("shelter") ?? true { shelterCheck(&b) }
    if parts?.contains("built") ?? true { builtCheck(&b) }
    if parts?.contains("fright") ?? true { frightCheck(&b) }
    if parts?.contains("lookout") ?? true { lookoutCheck(&b) }
    if parts?.contains("more") ?? true { moreCheck(&b) }
    if parts?.contains("memory") ?? true { memoryCheck(&b) }
    if parts?.contains("life") ?? true { lifeCheck(&b) }
    print(b.fails == 0 ? "all ok" : "\(b.fails) FAILED")
}
#endif
